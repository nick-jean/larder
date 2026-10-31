import type { Confidence } from "./schema";

/** Canonical unit key → aliases as written in recipes (matched case-insensitively unless listed in CASE_SENSITIVE). */
export const UNITS: Record<string, string[]> = {
  tsp: ["teaspoon", "teaspoons", "tsp", "tsps", "tsp.", "teasp", "t"],
  tbsp: ["tablespoon", "tablespoons", "tbsp", "tbsps", "tbsp.", "tbs", "tbs.", "tbl", "tbl.", "T"],
  cup: ["cup", "cups", "c", "c."],
  floz: ["fl oz", "fl. oz", "fl. oz.", "fl oz.", "fluid ounce", "fluid ounces"],
  oz: ["ounce", "ounces", "oz", "oz."],
  lb: ["pound", "pounds", "lb", "lbs", "lb.", "lbs."],
  g: ["g", "gram", "grams", "gr", "g."],
  kg: ["kg", "kilogram", "kilograms", "kilo", "kilos", "kg."],
  ml: ["ml", "milliliter", "milliliters", "millilitre", "millilitres", "ml."],
  l: ["l", "liter", "liters", "litre", "litres"],
  pint: ["pint", "pints", "pt", "pt."],
  quart: ["quart", "quarts", "qt", "qt."],
  gallon: ["gallon", "gallons", "gal", "gal."],
  pinch: ["pinch", "pinches"],
  dash: ["dash", "dashes"],
  clove: ["clove", "cloves"],
  can: ["can", "cans"],
  package: ["package", "packages", "pkg", "pkg.", "packet", "packets"],
  stick: ["stick", "sticks"],
  slice: ["slice", "slices"],
  bunch: ["bunch", "bunches"],
  sprig: ["sprig", "sprigs"],
  handful: ["handful", "handfuls"],
  piece: ["piece", "pieces", "pc", "pcs"],
};

/** "t" is teaspoon and "T" tablespoon only in their exact case. */
const CASE_SENSITIVE = new Set(["t", "T"]);

const ALIASES: Array<[alias: string, unit: string]> = Object.entries(UNITS)
  .flatMap(([unit, aliases]) => aliases.map((a): [string, string] => [a, unit]))
  .sort((a, b) => b[0].length - a[0].length);

const VULGAR: Record<string, string> = {
  "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4", "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5",
  "⅙": "1/6", "⅚": "5/6", "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8",
};

/** Unicode fractions → "a/b" (with a space after a whole number), dashes → "-", fraction slash → "/". */
export function normalizeFractions(s: string): string {
  let out = s.replace(/[\u2044\u2215]/g, "/").replace(/[\u2010-\u2015\u2212]/g, "-");
  out = out.replace(/(\d)?([½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])/g, (_m, whole: string | undefined, frac: string) =>
    whole ? `${whole} ${VULGAR[frac]}` : VULGAR[frac],
  );
  return out;
}

const NUM = String.raw`(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?|\.\d+)`;
const QTY_RE = new RegExp(String.raw`^(${NUM})(?:\s*(?:-|to)\s*(${NUM}))?`);

export function parseNumber(s: string): number | null {
  const t = s.trim();
  let m = /^(\d+)\s+(\d+)\/(\d+)$/.exec(t);
  if (m) return Number(m[3]) === 0 ? null : Number(m[1]) + Number(m[2]) / Number(m[3]);
  m = /^(\d+)\/(\d+)$/.exec(t);
  if (m) return Number(m[2]) === 0 ? null : Number(m[1]) / Number(m[2]);
  const n = Number(t);
  return t !== "" && Number.isFinite(n) ? n : null;
}

/** Matches a unit alias at the start of [s]; returns the canonical unit and the alias text as written. */
export function matchUnit(s: string): { unit: string; raw: string } | null {
  for (const [alias, unit] of ALIASES) {
    const candidate = s.slice(0, alias.length);
    const same = CASE_SENSITIVE.has(alias) ? candidate === alias : candidate.toLowerCase() === alias.toLowerCase();
    if (!same) continue;
    const next = s.charAt(alias.length);
    // The alias must end at a word boundary ("cups" is not "c" + "ups").
    if (next !== "" && /[A-Za-z]/.test(next)) continue;
    if (alias.endsWith(".") === false && next === ".") return { unit, raw: s.slice(0, alias.length + 1) };
    return { unit, raw: candidate };
  }
  return null;
}

export interface ParsedIngredient {
  raw: string;
  isSection: boolean;
  quantity: number | null;
  quantityMax: number | null;
  unit: string | null;
  unitRaw: string | null;
  item: string;
  note: string | null;
  confidence: Confidence;
}

const NO_QTY_OK = /\b(to taste|to serve|for serving|for garnish|garnish|as needed|optional|some|a few|a little|handful|pinch|dash)\b/i;
const JUNK = /[|{}<>~^_=\\]|[a-z][0-9][a-z]|\d[OoIl]\b|\b[OoIl]\d/;


/** Removes list bullets and checkboxes. Numbered prefixes are removed only when followed by text ("1. cup" stays). */
export function stripBullet(line: string): string {
  return line.replace(/^\s*[-–—•*·▢□☐▪◦●○]+\s*/, "").trim();
}

function splitNote(rest: string): { item: string; note: string | null } {
  let depth = 0;
  for (let i = 0; i < rest.length; i++) {
    const ch = rest[i];
    if (ch === "(") depth++;
    else if (ch === ")") depth = Math.max(0, depth - 1);
    else if (ch === "," && depth === 0) {
      const item = rest.slice(0, i).trim();
      const note = rest.slice(i + 1).trim();
      if (item) return { item, note: note || null };
    }
  }
  return { item: rest.trim(), note: null };
}

export function isSectionHeader(line: string): boolean {
  const t = line.trim();
  if (!t || /^\d/.test(normalizeFractions(t))) return false;
  const words = t.replace(/:$/, "").split(/\s+/).length;
  if (t.endsWith(":") && words <= 6) return true;
  return /^for (the )?[a-z]/i.test(t) && words <= 5 && !t.includes(",");
}

export function parseIngredientLine(rawInput: string): ParsedIngredient {
  const raw = rawInput.trim();
  const line = stripBullet(raw);
  const base: ParsedIngredient = {
    raw, isSection: false, quantity: null, quantityMax: null, unit: null, unitRaw: null, item: "", note: null, confidence: "medium",
  };
  if (isSectionHeader(line)) {
    return { ...base, isSection: true, item: line.replace(/:\s*$/, "").trim(), confidence: "high" };
  }

  let rest = normalizeFractions(line);
  // "200g" → "200 g", "1½cups" → "1 1/2 cups"
  rest = rest.replace(/^(\d+(?:\.\d+)?|\d+\s+\d+\/\d+|\d+\/\d+)(?=[A-Za-z])/, "$1 ");

  let quantity: number | null = null;
  let quantityMax: number | null = null;
  const qm = QTY_RE.exec(rest);
  if (qm) {
    quantity = parseNumber(qm[1]);
    quantityMax = qm[2] ? parseNumber(qm[2]) : null;
    rest = rest.slice(qm[0].length).trim();
  } else {
    const am = /^(a|an|one)\s+(?=\S)/i.exec(rest);
    if (am && matchUnit(rest.slice(am[0].length))) {
      quantity = 1;
      rest = rest.slice(am[0].length);
    }
  }

  let sizeNote: string | null = null;
  if (quantity !== null) {
    const pm = /^\(([^)]{1,40})\)\s*/.exec(rest);
    if (pm) {
      sizeNote = pm[1].trim();
      rest = rest.slice(pm[0].length);
    }
  }

  let unit: string | null = null;
  let unitRaw: string | null = null;
  if (quantity !== null) {
    const um = matchUnit(rest);
    if (um) {
      unit = um.unit;
      unitRaw = um.raw;
      rest = rest.slice(um.raw.length).trim();
    }
  }
  rest = rest.replace(/^of\s+/i, "");

  const { item, note } = splitNote(rest);
  const fullNote = [sizeNote, note].filter(Boolean).join(", ") || null;

  let confidence: Confidence;
  if (quantity !== null) confidence = item ? "high" : "low";
  else confidence = NO_QTY_OK.test(line) ? "high" : "medium";
  if (JUNK.test(line)) confidence = "low";

  return { ...base, quantity, quantityMax, unit, unitRaw, item, note: fullNote, confidence };
}

/** Does the line look like an ingredient (quantity first, or a short noun phrase in a list)? */
export function looksLikeIngredient(line: string): boolean {
  const t = stripBullet(line);
  if (!t) return false;
  const n = normalizeFractions(t);
  if (QTY_RE.test(n.replace(/^(\d+)(?=[A-Za-z])/, "$1 "))) {
    // "350°F" or "20 minutes" at the start is not an ingredient.
    if (/^\d+\s*(°|degrees|min|minutes|hours?|hrs?|seconds?)\b/i.test(n)) return false;
    return t.length <= 90;
  }
  return /^(a|an)\s/i.test(t) && matchUnit(t.replace(/^(a|an)\s+/i, "")) !== null;
}


