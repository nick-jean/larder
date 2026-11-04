import { parseIngredientLine } from "./ingredient";
import type { IngredientLine, Provenance, RecipeDraft, StepLine } from "./schema";

export interface JsonLdRecipe {
  draft: RecipeDraft;
  author: string | null;
  imageUrl: string | null;
  siteName: string | null;
}

/** ISO-8601 duration ("PT1H20M") → minutes. */
export function parseIsoDuration(v: unknown): number | null {
  if (typeof v !== "string") return null;
  const m = /^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$/i.exec(v.trim());
  if (!m || !(m[1] || m[2] || m[3] || m[4])) return null;
  const minutes = Number(m[1] ?? 0) * 1440 + Number(m[2] ?? 0) * 60 + Number(m[3] ?? 0) + Number(m[4] ?? 0) / 60;
  return minutes > 0 ? Math.round(minutes) : null;
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", frac12: "½", frac14: "¼", frac34: "¾", deg: "°" };

export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z0-9]+);/gi, (m, e: string) => {
    if (e[0] === "#") {
      const code = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(code) && code > 0 && code < 0x110000 ? String.fromCodePoint(code) : m;
    }
    return ENTITIES[e.toLowerCase()] ?? m;
  });
}

function clean(v: unknown): string {
  if (typeof v !== "string") return "";
  return decodeEntities(v.replace(/<[^>]*>/g, " ")).replace(/\s+/g, " ").trim();
}

function isRecipe(node: unknown): node is Record<string, unknown> {
  if (!node || typeof node !== "object") return false;
  const t = (node as Record<string, unknown>)["@type"];
  return t === "Recipe" || (Array.isArray(t) && t.includes("Recipe"));
}

function findRecipe(node: unknown, depth = 0): Record<string, unknown> | null {
  if (depth > 6 || !node || typeof node !== "object") return null;
  if (Array.isArray(node)) {
    for (const n of node) {
      const r = findRecipe(n, depth + 1);
      if (r) return r;
    }
    return null;
  }
  if (isRecipe(node)) return node;
  const obj = node as Record<string, unknown>;
  for (const key of ["@graph", "mainEntity", "mainEntityOfPage", "itemListElement", "item"]) {
    const r = findRecipe(obj[key], depth + 1);
    if (r) return r;
  }
  return null;
}

function name(v: unknown): string | null {
  if (!v) return null;
  if (typeof v === "string") return clean(v) || null;
  if (Array.isArray(v)) return name(v[0]);
  if (typeof v === "object") return name((v as Record<string, unknown>).name);
  return null;
}

function image(v: unknown): string | null {
  if (!v) return null;
  if (typeof v === "string") return /^https?:\/\//.test(v) ? v : null;
  if (Array.isArray(v)) return image(v[0]);
  if (typeof v === "object") return image((v as Record<string, unknown>).url);
  return null;
}

function stepTexts(v: unknown, depth = 0): Array<{ text: string; section?: string }> {
  if (depth > 4 || !v) return [];
  if (typeof v === "string") {
    return clean(v.replace(/<\/(p|li)>|<br\s*\/?>/gi, "\n"))
      ? v.replace(/<\/(p|li)>|<br\s*\/?>/gi, "\n").split(/\n+/).map((s) => ({ text: clean(s) })).filter((s) => s.text)
      : [];
  }
  if (Array.isArray(v)) return v.flatMap((x) => stepTexts(x, depth + 1));
  if (typeof v === "object") {
    const o = v as Record<string, unknown>;
    if (o["@type"] === "HowToSection" || Array.isArray(o.itemListElement)) {
      const items = stepTexts(o.itemListElement, depth + 1);
      const section = clean(o.name);
      return section && items.length ? [{ text: section, section }, ...items] : items;
    }
    const text = clean(o.text) || clean(o.name);
    return text ? [{ text }] : [];
  }
  return [];
}

function servings(v: unknown): { servings: number | null; yieldText: string | null } {
  const values = Array.isArray(v) ? v : [v];
  let n: number | null = null;
  let text: string | null = null;
  for (const x of values) {
    if (typeof x === "number" && Number.isFinite(x)) n ??= x;
    else if (typeof x === "string") {
      const c = clean(x);
      const m = /(\d+)/.exec(c);
      if (m) n ??= Number(m[1]);
      if (c && !/^\d+$/.test(c)) text ??= c;
    }
  }
  return { servings: n, yieldText: text ?? (n !== null ? `Serves ${n}` : null) };
}

let counter = 0;
const defaultId = () => `j${Date.now().toString(36)}${(counter++).toString(36)}`;

/** Finds a schema.org Recipe in the page's JSON-LD scripts. */
export function extractJsonLdRecipe(html: string, newId: () => string = defaultId): JsonLdRecipe | null {
  const provenance: Provenance = "linked_page";
  const scripts = html.matchAll(/<script[^>]*type=["']?application\/ld\+json["']?[^>]*>([\s\S]*?)<\/script>/gi);
  for (const s of scripts) {
    let data: unknown;
    try {
      data = JSON.parse(s[1].trim().replace(/^<!--|-->$/g, ""));
    } catch {
      continue;
    }
    const r = findRecipe(data);
    if (!r) continue;

    const rawIngredients = (Array.isArray(r.recipeIngredient) ? r.recipeIngredient : Array.isArray(r.ingredients) ? r.ingredients : [])
      .map(clean)
      .filter(Boolean);
    const ingredients: IngredientLine[] = rawIngredients.map((raw) => {
      const p = parseIngredientLine(raw);
      return {
        id: newId(),
        raw: p.raw,
        isSection: p.isSection,
        quantity: p.quantity,
        quantityMax: p.quantityMax,
        unit: p.unit,
        unitRaw: p.unitRaw,
        item: p.item,
        note: p.note,
        confidence: p.confidence === "low" ? "medium" : "high",
        provenance,
        box: null,
      };
    });
    const steps: StepLine[] = stepTexts(r.recipeInstructions)
      .filter((s) => !s.section)
      .map((s) => ({ id: newId(), text: s.text, confidence: "high", provenance, box: null }));
    const { servings: n, yieldText } = servings(r.recipeYield);
    const title = clean(r.name);
    const site = /<meta[^>]+property=["']og:site_name["'][^>]+content=["']([^"']+)["']/i.exec(html)?.[1] ?? null;
    return {
      draft: {
        title,
        servings: n,
        yieldText,
        prepMinutes: parseIsoDuration(r.prepTime),
        cookMinutes: parseIsoDuration(r.cookTime),
        totalMinutes: parseIsoDuration(r.totalTime),
        ingredients,
        steps,
        fieldConfidence: { title: title ? "high" : "low", servings: "high", times: "high" },
        foundIn: [provenance],
      },
      author: name(r.author),
      imageUrl: image(r.image),
      siteName: site ? clean(site) : null,
    };
  }
  return null;
}

/** <title> or og:title, used when the page has no Recipe markup. */
export function pageTitle(html: string): string | null {
  const og = /<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i.exec(html)?.[1];
  const t = og ?? /<title[^>]*>([^<]*)<\/title>/i.exec(html)?.[1];
  return t ? clean(t) || null : null;
}
