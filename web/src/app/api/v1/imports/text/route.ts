import { classifyLink, missingParts, structureLines, TextImportRequest, type ImportResult, type InputLine } from "@larder/parser";
import { randomUUID } from "node:crypto";
import { aiConfigured, structureWithGemini } from "@/lib/ai";
import { collections } from "@/lib/db";
import { authed, HttpError, json, parseBody, requireDatabase } from "@/lib/http";
import { consumeRateLimits, paidLimits } from "@/lib/rate-limit";
import { consumeImport, getOrCreateUser, refundImport } from "@/lib/users";

/**
 * Structures pasted caption/recipe text or on-device OCR lines. Rules-based by default (free);
 * with ai=true (user opt-in) the text is tidied by an LLM whose output is grounded against the text.
 */
export const POST = authed(async (request, user) => {
  requireDatabase();
  const body = await parseBody(request, TextImportRequest);
  const lines: InputLine[] = body.lines?.length ? body.lines : [{ text: body.text ?? "" }];
  const sourceText = lines.map((l) => l.text).join("\n");
  let draft = structureLines(lines, body.provenance);
  let usedAi = false;

  if (body.ai) {
    if (!aiConfigured()) throw new HttpError(503, "AI tidy-up isn't available right now.");
    await getOrCreateUser(user);
    const limits = paidLimits("ai");
    await consumeRateLimits(user.uid, limits.account);
    await consumeRateLimits("global", limits.global);
    if (!(await consumeImport(user.uid))) throw new HttpError(402, "You've used this month's free AI tidy-ups.");
    try {
      const ai = await structureWithGemini(sourceText);
      if (ai && (ai.ingredients.length || ai.steps.length)) {
        draft = ai;
        usedAi = true;
      }
    } catch (err) {
      console.error(err);
    }
    if (!usedAi) await refundImport(user.uid);
  }

  const missing = missingParts(draft);
  const link = body.url ? classifyLink(body.url) : null;
  const result: ImportResult = {
    importId: randomUUID(),
    receipt: null,
    layers: [{ name: "user_text", status: "ok", detail: usedAi ? "AI tidy-up" : null }],
    draft: missing.length === 2 ? null : draft,
    needsUserText: missing.length > 0,
    classification: missing.length === 2 ? "not_recipe" : "recipe",
    message: missing.length === 2 ? "We couldn't find ingredients or steps in that text." : missing.length ? `No ${missing[0]} found. Add them or another screenshot.` : null,
  };
  const { imports } = await collections();
  await imports.insertOne({
    _id: result.importId,
    ownerId: user.uid,
    kind: "text",
    platform: link?.platform ?? null,
    url: link?.canonicalUrl ?? null,
    layers: ["user_text"],
    ai: usedAi,
    createdAt: new Date().toISOString(),
  });
  return json(result);
});
