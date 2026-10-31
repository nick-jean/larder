import { isSectionHeader, looksLikeIngredient, parseIngredientLine, stripBullet } from "./ingredient";
import type { Box, Confidence, IngredientLine, Provenance, RecipeDraft, StepLine } from "./schema";

export interface InputLine {
  text: string;
  /** OCR confidence 0..1; null/undefined for typed or fetched text. */
  confidence?: number | null;
  box?: Box | null;
}

export interface StructureOptions {
  newId?: () => string;
}

const RANK: Record<Confidence, number> = { low: 0, medium: 1, high: 2 };
export function minConfidence(...cs: Confidence[]): Confidence {
  return cs.reduce((a, b) => (RANK[b] < RANK[a] ? b : a), "high" as Confidence);
}

export function ocrConfidence(c: number | null | undefined): Confidence {
  if (c === null || c === undefined) return "high";
  if (c >= 0.85) return "high";
  if (c >= 0.6) return "medium";
  return "low";
}

/** "1 hr 20 min" → 80, "45 minutes" → 45, "1.5 hours" → 90. */
export function parseDuration(s: string): number | null {
  const m = /(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hours?)\b\.?(?:\s*(?:and\s*)?(\d+)\s*(?:m|min|mins|minutes?)\b)?|(\d+)\s*(?:m|min|mins|minutes?)\b/i.exec(s);
  if (!m) return null;
  if (m[1] !== undefined) return Math.round(Number(m[1]) * 60 + (m[2] ? Number(m[2]) : 0));
  return Number(m[3]);
}

const INGREDIENTS_HDR = /^(?:ingredients?|you(?:'|’)?ll need|what you(?:'|’)?ll need|what you need)\s*:?\s*$/i;
const STEPS_HDR = /^(?:instructions|directions|method|steps|preparation|how to make(?: it)?|to make)\s*:?\s*$/i;
const NUMBERED = /^(?:step\s*)?(\d{1,2})\s*[.):]\s*/i;
const VERBS =
  "preheat|heat|mix|stir|add|bake|boil|combine|whisk|cook|pour|serve|place|season|melt|bring|remove|transfer|let|cut|chop|slice|dice|toss|fold|simmer|roast|fry|saute|sauté|grill|blend|beat|spread|sprinkle|top|drain|reserve|cover|line|grease|knead|roll|marinate|garnish|enjoy|set|put|make|start|finish|wash|peel|mince|grate|press|chill|refrigerate|freeze|cream|microwave|air fry|layer|repeat|flip|reduce|turn|allow|use|in a|in another|once|when|while|meanwhile|then|after|finally";
const IMPERATIVE = new RegExp(`^(?:${VERBS})\\b`, "i");
const SERVINGS = /\b(?:serves|servings?|makes|yields?|portions?)\s*:?\s*(\d+)(?:\s*(?:-|–|to)\s*\d+)?|(\d+)(?:\s*(?:-|–|to)\s*\d+)?\s*(?:servings|portions|people)\b/i;
const TIME_LABEL = /\b(prep|preparation|cook|cooking|bake|baking|total|active|ready in)\b(?:\s*time)?\s*:?/i;
const TEMP = /\b\d{3}\s*°?\s*(?:f|c|degrees)\b|°/i;

export function isStepLike(line: string): boolean {
  const t = stripBullet(line);
  if (NUMBERED.test(t) && !looksLikeIngredient(t.replace(NUMBERED, ""))) return true;
  if (IMPERATIVE.test(t)) return true;
  return t.length > 70 && /[.!]$/.test(t);
}

function cleanText(s: string): string {
  return s
    .replace(/(?:https?:\/\/|www\.)\S+/gi, "")
    .replace(/(?:^|\s)#[\p{L}\p{N}_]+/gu, " ")
    .replace(/\b(?:(?:full )?recipe )?(?:link )?in (?:my )?bio\b|\bfollow (?:me|us) for more\b.*$/gi, "")
    .replace(/\s+/g, " ")
    .trim();
}

function cleanTitle(s: string): string {
  let t = s.replace(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/gu, "").replace(/\s+/g, " ").trim();
  t = t.replace(/^(?:recipe|title)\s*:\s*/i, "").replace(/[\s:|\-–—·]+$/, "");
  if (t.length > 100) {
    const sentence = /^(.{10,100}?)[.!?](\s|$)/.exec(t);
    t = sentence ? sentence[1] : `${t.slice(0, 80).trim()}…`;
  }
  return t;
}

const NOISE = /^(?:follow\b|like and\b|save (?:this|for later)|comment\b|link in (?:my )?bio|full recipe (?:on|at|in)\b|recipe (?:on|at|in) (?:my )?(?:bio|blog|website)|tag a friend|#)/i;

interface Meta {
  servings: number | null;
  yieldText: string | null;
  prep: number | null;
  cook: number | null;
  total: number | null;
}

/** Parses "Serves 4 · Prep 10 min · Cook 20 min" style lines. Returns false if the line has anything else. */
function readMeta(line: string, meta: Meta): boolean {
  if (line.length > 80 || looksLikeIngredient(line)) return false;
  const segments = line.split(/\s*[·|•;,]\s*|\s+-\s+/).filter(Boolean);
  const found: Partial<Meta> = {};
  for (const seg of segments) {
    const s = SERVINGS.exec(seg);
    if (s) {
      found.servings = Number(s[1] ?? s[2]);
      found.yieldText = seg.trim();
      continue;
    }
    const label = TIME_LABEL.exec(seg);
    const minutes = parseDuration(seg);
    if (minutes !== null && (label || seg.replace(/[\d.\s]|h(?:ou)?rs?|hours?|m(?:in(?:ute)?s?)?|and/gi, "").length <= 2)) {
      const kind = label?.[1].toLowerCase() ?? "total";
      if (kind.startsWith("prep") || kind === "active") found.prep = minutes;
      else if (kind.startsWith("cook") || kind.startsWith("bak")) found.cook = minutes;
      else found.total = minutes;
      continue;
    }
    if (TEMP.test(seg) && seg.length <= 25) continue;
    return false;
  }
  if (Object.keys(found).length === 0) return false;
  meta.servings ??= found.servings ?? null;
  meta.yieldText ??= found.yieldText ?? null;
  meta.prep ??= found.prep ?? null;
  meta.cook ??= found.cook ?? null;
  meta.total ??= found.total ?? null;
  return true;
}

let counter = 0;
const defaultId = () => `l${Date.now().toString(36)}${(counter++).toString(36)}`;

/**
 * Turns caption, pasted or OCR text into a draft recipe. Nothing is invented: absent fields stay null,
 * and uncertain lines carry low/medium confidence for the review screen.
 */
export function structureLines(input: InputLine[], provenance: Provenance, options: StructureOptions = {}): RecipeDraft {
  const newId = options.newId ?? defaultId;
  const meta: Meta = { servings: null, yieldText: null, prep: null, cook: null, total: null };
  const ingredients: IngredientLine[] = [];
  const steps: StepLine[] = [];
  let title = "";
  let titleConf: Confidence = "high";
  let metaConf: Confidence = "high";
  let mode: "pre" | "ingredients" | "steps" = "pre";

  const lines = input
    .flatMap((l) => l.text.split(/\r?\n/).map((text) => ({ ...l, text })))
    .map((l) => ({ ...l, text: cleanText(l.text) }))
    .filter((l) => l.text && !NOISE.test(l.text));

  const addStep = (text: string, l: InputLine) => {
    const conf = ocrConfidence(l.confidence);
    const prev = steps.at(-1);
    const prevPage = prev?.box?.page;
    const continues =
      prev && !NUMBERED.test(text) && !/[.!?)]$/.test(prev.text) && /^[a-z(]/.test(text);
    if (prev && continues) {
      prev.text = `${prev.text} ${text}`;
      prev.confidence = minConfidence(prev.confidence, conf);
      if (l.box && prevPage !== undefined && l.box.page !== prevPage) {
        prev.seam = true;
        prev.confidence = minConfidence(prev.confidence, "medium");
      }
      return;
    }
    const body = text.replace(NUMBERED, "").trim();
    if (!body) return;
    steps.push({ id: newId(), text: body, confidence: conf, provenance, box: l.box ?? null });
  };

  const addIngredient = (text: string, l: InputLine) => {
    const p = parseIngredientLine(text);
    if (!p.item && !p.isSection) return;
    ingredients.push({
      id: newId(),
      raw: p.raw,
      isSection: p.isSection,
      quantity: p.quantity,
      quantityMax: p.quantityMax,
      unit: p.unit,
      unitRaw: p.unitRaw,
      item: p.item,
      note: p.note,
      confidence: minConfidence(p.confidence, ocrConfidence(l.confidence)),
      provenance,
      box: l.box ?? null,
    });
  };

  for (const l of lines) {
    const text = l.text;
    if (INGREDIENTS_HDR.test(text)) {
      mode = "ingredients";
      continue;
    }
    if (STEPS_HDR.test(text)) {
      mode = "steps";
      continue;
    }
    if (mode !== "steps" && readMeta(text, meta)) {
      metaConf = minConfidence(metaConf, ocrConfidence(l.confidence));
      continue;
    }
    if (mode === "steps") {
      addStep(text, l);
      continue;
    }
    if (mode === "ingredients") {
      if (isSectionHeader(text) || looksLikeIngredient(text) || !isStepLike(text)) addIngredient(text, l);
      else {
        mode = "steps";
        addStep(text, l);
      }
      continue;
    }
    // No header seen yet: classify each line.
    if (title && steps.length === 0 && isSectionHeader(text)) {
      mode = "ingredients";
      addIngredient(text, l);
    } else if (looksLikeIngredient(text)) addIngredient(text, l);
    // Short unquantified lines right after ingredients ("Salt to taste") are still ingredients.
    else if (ingredients.length > 0 && steps.length === 0 && !isStepLike(text) && text.length <= 40 && !/[.!?]$/.test(text)) addIngredient(text, l);
    else if (steps.length > 0 || ingredients.length > 0 || isStepLike(text)) addStep(text, l);
    else if (!title) {
      title = cleanTitle(text);
      titleConf = minConfidence(provenance === "linked_page" ? "high" : "medium", ocrConfidence(l.confidence));
    }
    // Other free text before the recipe (headnotes, chatter) is dropped.
  }

  const foundIn: Provenance[] = ingredients.length || steps.length || title ? [provenance] : [];
  return {
    title,
    servings: meta.servings,
    yieldText: meta.yieldText,
    prepMinutes: meta.prep,
    cookMinutes: meta.cook,
    totalMinutes: meta.total,
    ingredients,
    steps,
    fieldConfidence: { title: title ? titleConf : "low", servings: metaConf, times: metaConf },
    foundIn,
  };
}

export function structureText(text: string, provenance: Provenance, options: StructureOptions = {}): RecipeDraft {
  return structureLines([{ text }], provenance, options);
}

/** What the draft still lacks, for the "add a screenshot?" prompt. */
export function missingParts(draft: RecipeDraft | null): Array<"ingredients" | "steps"> {
  if (!draft) return ["ingredients", "steps"];
  const out: Array<"ingredients" | "steps"> = [];
  if (!draft.ingredients.some((i) => !i.isSection)) out.push("ingredients");
  if (draft.steps.length === 0) out.push("steps");
  return out;
}
