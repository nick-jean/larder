const FRACTIONS: Array<[number, string]> = [
  [1 / 8, "⅛"], [1 / 4, "¼"], [1 / 3, "⅓"], [3 / 8, "⅜"], [1 / 2, "½"], [5 / 8, "⅝"], [2 / 3, "⅔"], [3 / 4, "¾"], [7 / 8, "⅞"],
];

function trimDecimal(n: number, places: number): string {
  return String(Number(n.toFixed(places)));
}

/** 1.5 → "1½", 0.333 → "⅓", 2 → "2", 0.15 → "0.15". */
export function formatQuantity(q: number): string {
  if (!Number.isFinite(q)) return "";
  if (q < 0) return `-${formatQuantity(-q)}`;
  let whole = Math.floor(q);
  let frac = q - whole;
  if (frac < 0.02) return String(whole);
  if (frac > 0.98) return String(whole + 1);
  for (const [value, glyph] of FRACTIONS) {
    if (Math.abs(frac - value) <= 0.02) return whole > 0 ? `${whole}${glyph}` : glyph;
  }
  whole = 0;
  frac = q;
  return trimDecimal(frac, q < 1 ? 2 : 1);
}

export function formatRange(q: number | null, max: number | null): string {
  if (q === null) return "";
  return max !== null ? `${formatQuantity(q)}–${formatQuantity(max)}` : formatQuantity(q);
}

export type UnitSystem = "us" | "metric";

const US_VOLUME_ML: Record<string, number> = { tsp: 4.92892, tbsp: 14.7868, cup: 236.588, floz: 29.5735, pint: 473.176, quart: 946.353, gallon: 3785.41 };
const US_WEIGHT_G: Record<string, number> = { oz: 28.3495, lb: 453.592 };
const METRIC_VOLUME_ML: Record<string, number> = { ml: 1, l: 1000 };
const METRIC_WEIGHT_G: Record<string, number> = { g: 1, kg: 1000 };

function roundTo(x: number, step: number): number {
  // Second rounding strips float noise (1.9000000000000001 → 1.9).
  return Math.round(Math.round(x / step) * step * 1e6) / 1e6;
}

function roundMetric(x: number): number {
  if (x < 10) return roundTo(x, 0.5);
  if (x < 250) return Math.round(x);
  return roundTo(x, 5);
}

export interface Converted {
  quantity: number;
  quantityMax: number | null;
  unit: string;
}

function toMetric(q: number, unit: string): { q: number; unit: string } | null {
  if (unit in US_VOLUME_ML) {
    const ml = q * US_VOLUME_ML[unit];
    return ml >= 1000 ? { q: roundTo(ml / 1000, 0.05), unit: "l" } : { q: roundMetric(ml), unit: "ml" };
  }
  if (unit in US_WEIGHT_G) {
    const g = q * US_WEIGHT_G[unit];
    return g >= 1000 ? { q: roundTo(g / 1000, 0.05), unit: "kg" } : { q: roundMetric(g), unit: "g" };
  }
  return null;
}

function toUs(q: number, unit: string): { q: number; unit: string } | null {
  if (unit in METRIC_VOLUME_ML) {
    const ml = q * METRIC_VOLUME_ML[unit];
    if (ml < 15) return { q: roundTo(ml / US_VOLUME_ML.tsp, 0.25), unit: "tsp" };
    if (ml < 60) return { q: roundTo(ml / US_VOLUME_ML.tbsp, 0.5), unit: "tbsp" };
    if (ml < 1900) return { q: roundTo(ml / US_VOLUME_ML.cup, 0.25), unit: "cup" };
    return { q: roundTo(ml / US_VOLUME_ML.quart, 0.25), unit: "quart" };
  }
  if (unit in METRIC_WEIGHT_G) {
    const g = q * METRIC_WEIGHT_G[unit];
    if (g < US_WEIGHT_G.lb) return { q: roundTo(g / US_WEIGHT_G.oz, 0.25), unit: "oz" };
    return { q: roundTo(g / US_WEIGHT_G.lb, 0.25), unit: "lb" };
  }
  return null;
}

/** Converts a quantity to [system]; returns null when the unit is already in that system or not convertible. */
export function convertQuantity(q: number, max: number | null, unit: string | null, system: UnitSystem): Converted | null {
  if (!unit) return null;
  const fn = system === "metric" ? toMetric : toUs;
  const a = fn(q, unit);
  if (!a) return null;
  if (max === null) return { quantity: a.q, quantityMax: null, unit: a.unit };
  // Convert the upper bound into the same unit as the lower one.
  const ratio = q === 0 ? null : a.q / q;
  const round = (x: number) => (system === "us" ? roundTo(x, 0.25) : a.unit === "l" || a.unit === "kg" ? roundTo(x, 0.05) : roundMetric(x));
  const b = ratio === null ? fn(max, unit) : { q: round(max * ratio), unit: a.unit };
  return { quantity: a.q, quantityMax: b?.q ?? null, unit: a.unit };
}

const LABELS: Record<string, [string, string]> = {
  tsp: ["tsp", "tsp"], tbsp: ["tbsp", "tbsp"], cup: ["cup", "cups"], floz: ["fl oz", "fl oz"], oz: ["oz", "oz"], lb: ["lb", "lb"],
  g: ["g", "g"], kg: ["kg", "kg"], ml: ["ml", "ml"], l: ["l", "l"], pint: ["pint", "pints"], quart: ["quart", "quarts"], gallon: ["gallon", "gallons"],
};

/** Display label for a canonical unit, pluralised for quantities above 1. */
export function unitLabel(unit: string, quantity: number | null): string {
  const pair = LABELS[unit];
  if (!pair) return unit;
  return quantity !== null && quantity > 1 ? pair[1] : pair[0];
}

export function scaleQuantity(q: number | null, factor: number): number | null {
  return q === null ? null : q * factor;
}
