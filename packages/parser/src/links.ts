import type { Platform } from "./schema";

export interface ClassifiedLink {
  platform: Platform;
  canonicalUrl: string;
  creatorHandle: string | null;
  postId: string | null;
  /** Short/share links (vm.tiktok.com, fb.watch, …) that must be resolved before oEmbed. */
  isShortLink: boolean;
}

const TRACKING = /^(utm_.*|igsh|igshid|is_from_webapp|sender_device|sender_web_id|_r|_t|fbclid|mibextid|si|share_id|share_app_id|share_link_id|tt_from|u_code|user_id|timestamp|rdid|sharer_language|refer|ref|source|web_id|_d|checksum|sec_uid|share_item_id|preview_pb|region|social_sharing|lang)$/i;

/** Parses user input into a URL (adds https:// when the scheme is missing). Returns null for non-web input. */
export function toUrl(input: string): URL | null {
  const trimmed = input.trim().replace(/[)\].,!?'"]+$/, "");
  if (!trimmed || /\s/.test(trimmed)) return null;
  const withScheme = /^[a-z][a-z0-9+.-]*:/i.test(trimmed) ? trimmed : `https://${trimmed}`;
  try {
    const url = new URL(withScheme);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    if (!url.hostname.includes(".")) return null;
    return url;
  } catch {
    return null;
  }
}

function host(url: URL): string {
  return url.hostname.toLowerCase().replace(/^(www|m|mobile|web)\./, "");
}

export function classifyLink(input: string): ClassifiedLink | null {
  const url = toUrl(input);
  if (!url) return null;
  const h = host(url);
  url.hash = "";
  for (const key of [...url.searchParams.keys()]) if (TRACKING.test(key)) url.searchParams.delete(key);
  url.protocol = "https:";
  url.hostname = url.hostname.toLowerCase();
  const path = url.pathname.replace(/\/+$/, "");

  if (h === "tiktok.com" || h.endsWith(".tiktok.com")) {
    if (h === "vm.tiktok.com" || h === "vt.tiktok.com" || /^\/t\//.test(path)) {
      return { platform: "tiktok", canonicalUrl: url.toString(), creatorHandle: null, postId: null, isShortLink: true };
    }
    const m = /^\/@([\w.-]+)\/(?:video|photo)\/(\d+)/.exec(path);
    return {
      platform: "tiktok",
      canonicalUrl: m ? `https://www.tiktok.com/@${m[1]}/video/${m[2]}` : url.toString(),
      creatorHandle: m ? `@${m[1]}` : (/^\/@([\w.-]+)/.exec(path)?.[1] ? `@${/^\/@([\w.-]+)/.exec(path)![1]}` : null),
      postId: m ? m[2] : null,
      isShortLink: false,
    };
  }
  if (h === "instagram.com" || h === "instagr.am") {
    const m = /^\/(?:[\w.]+\/)?(p|reel|reels|tv)\/([\w-]+)/.exec(path);
    const kind = m ? (m[1] === "reels" ? "reel" : m[1]) : null;
    return {
      platform: "instagram",
      canonicalUrl: m ? `https://www.instagram.com/${kind}/${m[2]}/` : url.toString(),
      creatorHandle: null,
      postId: m ? m[2] : null,
      isShortLink: false,
    };
  }
  if (h === "facebook.com" || h === "fb.watch" || h === "fb.com" || h.endsWith(".facebook.com")) {
    const isShort = h === "fb.watch" || /^\/share\//.test(path);
    const reel = /^\/reel\/(\d+)/.exec(path);
    const video = /\/videos\/(?:[\w.-]+\/)?(\d+)/.exec(path);
    const watch = path === "/watch" ? url.searchParams.get("v") : null;
    const postId = reel?.[1] ?? video?.[1] ?? watch ?? null;
    const owner = /^\/([\w.]+)\/(?:videos|posts)\//.exec(path)?.[1] ?? null;
    let canonical = url.toString();
    if (reel) canonical = `https://www.facebook.com/reel/${reel[1]}`;
    else if (watch) canonical = `https://www.facebook.com/watch/?v=${watch}`;
    return { platform: "facebook", canonicalUrl: canonical, creatorHandle: owner, postId, isShortLink: isShort };
  }
  return { platform: "web", canonicalUrl: url.toString(), creatorHandle: null, postId: null, isShortLink: false };
}

/** URLs found in free text (captions), in order, without trailing punctuation. */
export function extractUrls(text: string): string[] {
  const out: string[] = [];
  const re = /\b((?:https?:\/\/|www\.)[^\s<>"']+|(?:[a-z0-9-]+\.)+(?:com|net|org|co|io|blog|recipes|kitchen|food)\/[^\s<>"']*)/gi;
  for (const m of text.matchAll(re)) {
    const url = toUrl(m[1]);
    if (url && !out.includes(url.toString())) out.push(url.toString());
  }
  return out;
}

export function isSocialPlatform(p: Platform): boolean {
  return p !== "web";
}
