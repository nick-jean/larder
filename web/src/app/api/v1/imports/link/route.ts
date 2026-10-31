import { classifyLink, LinkImportRequest } from "@larder/parser";
import { randomUUID } from "node:crypto";
import { collections } from "@/lib/db";
import { authed, HttpError, json, parseBody, requireDatabase } from "@/lib/http";
import { getFetcher, importLink, type LinkImport } from "@/lib/link-import";
import { consumeRateLimits, linkImportLimits } from "@/lib/rate-limit";
import { consumeImport, getOrCreateUser } from "@/lib/users";

const CACHE_MS = 7 * 24 * 60 * 60 * 1000;
export const POST = authed(async (request, user) => {
  requireDatabase();
  const { url } = await parseBody(request, LinkImportRequest);
  const link = classifyLink(url);
  if (!link) throw new HttpError(400, "That doesn't look like a link.");
  await consumeRateLimits(user.uid, linkImportLimits());
  await getOrCreateUser(user);
  const { linkCache, imports } = await collections();

  const cached = link.isShortLink ? null : await linkCache.findOne({ _id: link.canonicalUrl, expiresAt: { $gt: new Date() } });
  let result: LinkImport;
  if (cached) result = cached.result;
  else {
    result = await importLink(url, getFetcher(), { metaToken: process.env.META_OEMBED_TOKEN });
    const transient = result.layers.some((l) => l.status === "error");
    if (!transient) {
      // Cached under the submitted URL too, so a link that redirects still hits the cache next time.
      const keys = new Set([result.receipt!.canonicalUrl, ...(link.isShortLink ? [] : [link.canonicalUrl])]);
      for (const _id of keys) {
        await linkCache.updateOne({ _id }, { $set: { result, expiresAt: new Date(Date.now() + CACHE_MS) } }, { upsert: true });
      }
    }
  }

  // Social imports that produced a recipe count against the monthly allowance; web imports are unlimited.
  if (result.draft && link.platform !== "web" && !(await consumeImport(user.uid))) {
    throw new HttpError(402, "You've used this month's free social imports. Paste the recipe text instead, or upgrade to Larder Plus.");
  }

  const importId = randomUUID();
  await imports.insertOne({
    _id: importId,
    ownerId: user.uid,
    kind: "link",
    platform: result.receipt?.platform ?? link.platform,
    url: result.receipt?.canonicalUrl ?? link.canonicalUrl,
    layers: result.layers.filter((l) => l.status === "ok").map((l) => l.name),
    ai: false,
    createdAt: new Date().toISOString(),
  });
  return json({ importId, ...result });
});
