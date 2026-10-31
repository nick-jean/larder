import { normalizeFractions, parseNumber } from "./ingredient";
import type { RecipeDraft } from "./schema";
import { minConfidence } from "./text";

function numbersIn(text: string): number[] {
  const out: number[] = [];
  const norm = normalizeFractions(text);
  for (const m of norm.matchAll(/\d+\s+\d+\/\d+|\d+\/\d+|\d+(?:\.\d+)?/g)) {
    const n = parseNumber(m[0]);
    if (n !== null) out.push(n);
  }
  return out;
}

function words(text: string): Set<string> {
  return new Set(text.toLowerCase().match(/[\p{L}]{3,}/gu) ?? []);
}

/**
 * Checks an LLM-structured draft against the source text it came from. Quantities that do not appear
 * in the source are removed (never invented), and lines with little word overlap are marked low confidence.
 */
export function groundDraft(draft: RecipeDraft, source: string): RecipeDraft {
  const nums = numbersIn(source);
  const has = (n: number) => nums.some((x) => Math.abs(x - n) < 0.01);
  // An ingredient quantity must appear on a source line that also names that ingredient.
  const lines = source.split("\n").map((l) => ({ nums: numbersIn(l), words: words(l) }));
  const hasFor = (n: number, item: string) => {
    const w = [...words(item)];
    if (w.length === 0) return has(n);
    return lines.some((l) => l.nums.some((x) => Math.abs(x - n) < 0.01) && w.some((x) => l.words.has(x)));
  };
  const vocab = words(source);
  const overlap = (text: string) => {
    const w = [...words(text)];
    return w.length === 0 ? 1 : w.filter((x) => vocab.has(x)).length / w.length;
  };

  const ingredients = draft.ingredients.map((i) => {
    const next = { ...i, provenance: "llm" as const };
    if (i.quantity !== null && !hasFor(i.quantity, i.item)) {
      next.quantity = null;
      next.quantityMax = null;
      next.confidence = "low";
    }
    if (i.quantityMax !== null && next.quantityMax !== null && !hasFor(i.quantityMax, i.item)) {
      next.quantityMax = null;
      next.confidence = "low";
    }
    if (overlap(`${i.item} ${i.note ?? ""}`) < 0.6) next.confidence = "low";
    else next.confidence = minConfidence(next.confidence, "medium");
    return next;
  });
  const steps = draft.steps.map((s) => ({
    ...s,
    provenance: "llm" as const,
    confidence: overlap(s.text) < 0.6 ? ("low" as const) : minConfidence(s.confidence, "medium"),
  }));
  const servings = draft.servings !== null && has(draft.servings) ? draft.servings : null;
  const keepTime = (m: number | null) => (m !== null && (has(m) || has(m / 60)) ? m : null);
  return {
    ...draft,
    title: overlap(draft.title) >= 0.5 ? draft.title : "",
    servings,
    // The yield text must be from the source too, or it would show the servings we just rejected.
    yieldText: draft.yieldText && numbersIn(draft.yieldText).every(has) && overlap(draft.yieldText) >= 0.5 ? draft.yieldText : null,
    prepMinutes: keepTime(draft.prepMinutes),
    cookMinutes: keepTime(draft.cookMinutes),
    totalMinutes: keepTime(draft.totalMinutes),
    ingredients,
    steps,
    fieldConfidence: {
      title: overlap(draft.title) >= 0.5 ? "medium" : "low",
      servings: "medium",
      times: "medium",
    },
    foundIn: [...new Set([...draft.foundIn, "llm" as const])],
  };
}
