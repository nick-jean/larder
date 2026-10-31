import { groundDraft, parseIngredientLine, type RecipeDraft } from "@larder/parser";
import { z } from "zod";

const MODEL = process.env.GEMINI_MODEL ?? "gemini-2.5-flash-lite";

export function aiConfigured(): boolean {
  return Boolean(process.env.GEMINI_API_KEY);
}

const ModelOutput = z.object({
  title: z.string().max(300).catch(""),
  servings: z.number().nullable().catch(null),
  prepMinutes: z.number().int().nullable().catch(null),
  cookMinutes: z.number().int().nullable().catch(null),
  totalMinutes: z.number().int().nullable().catch(null),
  ingredients: z.array(z.string().max(500)).max(300).catch([]),
  steps: z.array(z.string().max(4000)).max(300).catch([]),
});

export function buildPrompt(text: string): string {
  return [
    "Structure the recipe in the text below. Copy ingredient lines and steps from the text; never invent quantities, ingredients or steps that are not in it.",
    "Keep units as written. Use null for anything the text does not state. Section headings (e.g. \"For the sauce\") are ingredient lines ending with a colon.",
    'Return JSON: {"title":string,"servings":number|null,"prepMinutes":int|null,"cookMinutes":int|null,"totalMinutes":int|null,"ingredients":[string],"steps":[string]}',
    "Text:",
    text.slice(0, 20_000),
  ].join("\n");
}

let counter = 0;
const newId = () => `a${Date.now().toString(36)}${(counter++).toString(36)}`;

export function parseModelOutput(raw: string, source: string): RecipeDraft | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  const out = ModelOutput.safeParse(parsed);
  if (!out.success) return null;
  const v = out.data;
  const draft: RecipeDraft = {
    title: v.title.trim(),
    servings: v.servings,
    yieldText: v.servings !== null ? `Serves ${v.servings}` : null,
    prepMinutes: v.prepMinutes,
    cookMinutes: v.cookMinutes,
    totalMinutes: v.totalMinutes,
    ingredients: v.ingredients.map((line) => {
      const p = parseIngredientLine(line);
      return { id: newId(), ...p, raw: p.raw, provenance: "llm" as const, box: null };
    }),
    steps: v.steps.map((text) => ({ id: newId(), text: text.trim(), confidence: "medium" as const, provenance: "llm" as const, box: null })),
    fieldConfidence: { title: "medium", servings: "medium", times: "medium" },
    foundIn: ["llm"],
  };
  return groundDraft(draft, source);
}

/** Opt-in LLM structuring of user text (paid; caller enforces consent and rate limits). */
export async function structureWithGemini(text: string): Promise<RecipeDraft | null> {
  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`, {
    method: "POST",
    signal: AbortSignal.timeout(25_000),
    headers: { "content-type": "application/json", "x-goog-api-key": process.env.GEMINI_API_KEY! },
    body: JSON.stringify({
      contents: [{ parts: [{ text: buildPrompt(text) }] }],
      generationConfig: { responseMimeType: "application/json", temperature: 0 },
    }),
  });
  if (!res.ok) throw new Error(`Gemini request failed: ${res.status}`);
  const data = (await res.json()) as { candidates?: { content?: { parts?: { text?: string }[] } }[] };
  return parseModelOutput(data.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("") ?? "", text);
}
