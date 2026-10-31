import {
  classifyLink,
  extractJsonLdRecipe,
  extractUrls,
  missingParts,
  pageTitle,
  structureText,
  type ClassifiedLink,
  type ImportLayer,
  type ImportResult,
  type LinkReceipt,
  type RecipeDraft,
} from "@larder/parser";
import { BlockedUrlError, safeFetch, type Fetcher } from "./safe-fetch";

let fetcher: Fetcher = safeFetch;

export function getFetcher(): Fetcher {
  return fetcher;
}

/** For tests: replace outbound fetching. */
export function setFetcherForTesting(f: Fetcher | null): void {
  fetcher = f ?? safeFetch;
}

export type LinkImport = Omit<ImportResult, "importId">;

const PLATFORM_NAME = { tiktok: "TikTok", instagram: "Instagram", facebook: "Facebook", web: "the site" } as const;

interface OEmbed {
  title?: string;
  author_name?: string;
  author_unique_id?: string;
  author_url?: string;
  thumbnail_url?: string;
}

async function getJson(fetcher: Fetcher, url: string): Promise<{ status: number; data: OEmbed | null }> {
  const res = await fetcher(url, { accept: "application/json" });
  if (res.status !== 200) return { status: res.status, data: null };
  try {
    return { status: 200, data: JSON.parse(res.body) as OEmbed };
  } catch {
    return { status: res.status, data: null };
  }
}

function metaOembedUrl(link: ClassifiedLink, token: string): string {
  const endpoint = link.platform === "instagram" ? "instagram_oembed" : link.canonicalUrl.includes("/videos/") || link.canonicalUrl.includes("/reel/") || link.canonicalUrl.includes("/watch") ? "oembed_video" : "oembed_post";
  return `https://graph.facebook.com/v23.0/${endpoint}?url=${encodeURIComponent(link.canonicalUrl)}&omitscript=true&access_token=${encodeURIComponent(token)}`;
}

function hasContent(d: RecipeDraft | null): d is RecipeDraft {
  return Boolean(d && (d.ingredients.some((i) => !i.isSection) || d.steps.length > 0));
}

/** Copies attribution-free fields from the linked page and merges in caption-only parts. */
function mergeDrafts(page: RecipeDraft, caption: RecipeDraft | null): RecipeDraft {
  if (!hasContent(caption)) return page;
  return {
    ...page,
    ingredients: page.ingredients.length ? page.ingredients : caption.ingredients,
    steps: page.steps.length ? page.steps : caption.steps,
    servings: page.servings ?? caption.servings,
    foundIn: [...new Set([...page.foundIn, ...caption.foundIn])],
  };
}

function snippet(s: string | null | undefined): string | null {
  if (!s) return null;
  const t = s.replace(/\s+/g, " ").trim();
  return t.length > 200 ? `${t.slice(0, 197)}…` : t || null;
}

/**
 * Layered import for one link, using public official sources only:
 * resolve short link → oEmbed caption (TikTok; Meta when configured) → linked recipe page JSON-LD → caption text.
 * Never logs in, never scrapes Instagram/Facebook pages and never downloads video.
 */
export async function importLink(input: string, fetcher: Fetcher, env: { metaToken?: string } = {}): Promise<LinkImport> {
  let link = classifyLink(input);
  if (!link) throw new Error("not a link");
  const layers: ImportLayer[] = [];
  const layer = (name: ImportLayer["name"], status: ImportLayer["status"], detail: string | null = null) => layers.push({ name, status, detail });

  if (link.isShortLink) {
    try {
      const res = await fetcher(link.canonicalUrl);
      const resolved = classifyLink(res.finalUrl);
      if (resolved && resolved.platform === link.platform && !resolved.isShortLink) {
        link = resolved;
        layer("resolve", "ok");
      } else layer("resolve", "error", "Couldn't open the short link");
    } catch (err) {
      layer("resolve", "error", err instanceof BlockedUrlError ? err.message : "Couldn't open the short link");
    }
  } else layer("resolve", "skipped");

  const receipt: LinkReceipt = {
    platform: link.platform,
    url: input.trim(),
    canonicalUrl: link.canonicalUrl,
    creatorHandle: link.creatorHandle,
    creatorName: null,
    captionSnippet: null,
    thumbnailUrl: null,
  };
  let caption: string | null = null;
  let unavailable = false;

  if (link.platform === "tiktok") {
    try {
      const { status, data } = await getJson(fetcher, `https://www.tiktok.com/oembed?url=${encodeURIComponent(link.canonicalUrl)}`);
      if (data) {
        caption = data.title?.trim() || null;
        receipt.creatorName = data.author_name ?? null;
        receipt.creatorHandle = data.author_unique_id ? `@${data.author_unique_id}` : receipt.creatorHandle;
        receipt.thumbnailUrl = data.thumbnail_url ?? null;
        layer("oembed", caption ? "ok" : "none", caption ? null : "No caption on this post");
      } else {
        unavailable = status === 400 || status === 404;
        layer("oembed", "error", unavailable ? "Post is private or removed" : `TikTok returned ${status}`);
      }
    } catch {
      layer("oembed", "error", "TikTok didn't respond");
    }
  } else if (link.platform === "instagram" || link.platform === "facebook") {
    if (!env.metaToken) layer("oembed", "skipped", `${PLATFORM_NAME[link.platform]} doesn't share captions with apps`);
    else {
      try {
        const { status, data } = await getJson(fetcher, metaOembedUrl(link, env.metaToken));
        caption = data?.title?.trim() || null;
        receipt.creatorName = data?.author_name ?? null;
        receipt.thumbnailUrl = data?.thumbnail_url ?? null;
        layer("oembed", caption ? "ok" : data ? "none" : "error", caption ? null : data ? "No caption returned" : `${PLATFORM_NAME[link.platform]} returned ${status}`);
      } catch {
        layer("oembed", "error", `${PLATFORM_NAME[link.platform]} didn't respond`);
      }
    }
  }
  receipt.captionSnippet = snippet(caption);

  // Linked recipe page: the web link itself, or the first non-social URL in the caption.
  let pageDraft: RecipeDraft | null = null;
  let pageTitleText: string | null = null;
  const pageUrl = link.platform === "web" ? link.canonicalUrl : caption ? extractUrls(caption).find((u) => classifyLink(u)?.platform === "web") : undefined;
  if (pageUrl) {
    try {
      const res = await fetcher(pageUrl);
      if (res.status >= 400) {
        unavailable ||= link.platform === "web";
        layer("linked_page", "error", `Page returned ${res.status}`);
      } else {
        const found = extractJsonLdRecipe(res.body);
        pageTitleText = pageTitle(res.body);
        if (found && hasContent(found.draft)) {
          pageDraft = found.draft;
          if (link.platform === "web") {
            receipt.creatorName = found.author ?? found.siteName;
            receipt.thumbnailUrl = found.imageUrl;
            receipt.canonicalUrl = classifyLink(res.finalUrl)?.canonicalUrl ?? receipt.canonicalUrl;
          }
          layer("linked_page", "ok", found.siteName ?? new URL(res.finalUrl).hostname);
        } else layer("linked_page", "none", "No recipe markup on the page");
      }
    } catch (err) {
      layer("linked_page", "error", err instanceof BlockedUrlError ? err.message : "Couldn't open the page");
    }
  } else layer("linked_page", "skipped");

  let captionDraft: RecipeDraft | null = null;
  if (caption) {
    captionDraft = structureText(caption, "caption");
    layer("caption", hasContent(captionDraft) ? "ok" : "none", hasContent(captionDraft) ? null : "Caption has no recipe");
  } else if (link.platform !== "web") layer("caption", "skipped");

  let draft: RecipeDraft | null = pageDraft ? mergeDrafts(pageDraft, captionDraft) : hasContent(captionDraft) ? captionDraft : null;
  if (draft && !draft.title) draft = { ...draft, title: captionDraft?.title || pageTitleText || "" };
  const missing = missingParts(draft);
  const needsUserText = missing.length > 0;
  layer("user_text", needsUserText ? "none" : "skipped");

  let classification: LinkImport["classification"] = "recipe";
  let message: string | null = null;
  const name = PLATFORM_NAME[link.platform];
  if (unavailable && !draft) {
    classification = "unavailable";
    message = `This post is private, removed, or not public on ${name}. Paste the caption or add a screenshot instead.`;
  } else if (!draft && link.platform !== "web" && caption && !hasContent(captionDraft)) {
    classification = "not_recipe";
    message = "The caption doesn't include a recipe. If it's in the video, add a screenshot of the recipe or paste it.";
  } else if (!draft && (link.platform === "instagram" || link.platform === "facebook")) {
    message = `${name} doesn't let apps read captions. Paste the caption or add a screenshot. We'll keep the link and creator.`;
  } else if (!draft && link.platform === "web") {
    message = "We couldn't find a recipe on this page. Paste the recipe text or add a screenshot.";
  } else if (!draft) {
    message = "We couldn't read this post. Paste the caption or add a screenshot.";
  } else if (needsUserText) {
    message = `${missing.includes("steps") ? "Steps" : "Ingredients"} weren't in the ${pageDraft ? "page" : "caption"}. Add a screenshot or paste them.`;
  }

  return { receipt, layers, draft, needsUserText, classification, message };
}
