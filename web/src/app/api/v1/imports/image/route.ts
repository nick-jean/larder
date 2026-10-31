import { ImageImportRequest, missingParts, structureLines, type ImportResult, type InputLine } from "@larder/parser";
import { randomUUID } from "node:crypto";
import { collections } from "@/lib/db";
import { authed, HttpError, json, parseBody, requireDatabase } from "@/lib/http";
import { consumeRateLimits, paidLimits } from "@/lib/rate-limit";
import { consumeImport, getOrCreateUser, refundImport } from "@/lib/users";
import { ocrPage, visionConfigured } from "@/lib/vision";

export const maxDuration = 60;

/**
 * Opt-in cloud OCR for pages the on-device reader struggled with (messy handwriting).
 * Images are processed in memory and not stored.
 */
export const POST = authed(async (request, user) => {
  requireDatabase();
  if (!visionConfigured()) throw new HttpError(503, "Cloud reading isn't available right now.");
  const body = await parseBody(request, ImageImportRequest);
  await getOrCreateUser(user);
  const limits = paidLimits("ocr");
  await consumeRateLimits(user.uid, limits.account);
  await consumeRateLimits("global", limits.global);
  if (!(await consumeImport(user.uid))) throw new HttpError(402, "You've used this month's free cloud reads. The on-device result is still yours to edit.");

  let lines: InputLine[];
  try {
    lines = (await Promise.all(body.pages.map((p, i) => ocrPage(p, i)))).flat();
  } catch (err) {
    console.error(err);
    await refundImport(user.uid);
    throw new HttpError(502, "Cloud reading failed. Try again or edit the on-device result.");
  }
  const draft = structureLines(lines, "ocr");
  const missing = missingParts(draft);
  const result: ImportResult & { lines: InputLine[] } = {
    importId: randomUUID(),
    receipt: null,
    layers: [{ name: "user_text", status: "ok", detail: "Cloud OCR" }],
    draft: missing.length === 2 ? null : draft,
    needsUserText: missing.length > 0,
    classification: missing.length === 2 ? "not_recipe" : "recipe",
    message: missing.length === 2 ? "We couldn't read a recipe in these photos." : null,
    lines,
  };
  const { imports } = await collections();
  await imports.insertOne({
    _id: result.importId, ownerId: user.uid, kind: "image", platform: null, url: null, layers: ["ocr"], ai: false, createdAt: new Date().toISOString(),
  });
  return json(result);
});
