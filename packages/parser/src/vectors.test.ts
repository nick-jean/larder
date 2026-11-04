import { describe, expect, it } from "vitest";
import ingredients from "../vectors/ingredients.json";
import links from "../vectors/links.json";
import quantity from "../vectors/quantity.json";
import text from "../vectors/text.json";
import { classifyLink, convertQuantity, formatQuantity, parseIngredientLine, structureText, type Provenance, type UnitSystem } from "./index";

describe("ingredient vectors", () => {
  for (const v of ingredients) {
    it(v.raw, () => {
      const p = parseIngredientLine(v.raw);
      expect({ ...p, quantity: p.quantity === null ? null : Number(p.quantity.toFixed(6)) }).toEqual({
        raw: v.raw,
        isSection: v.isSection,
        quantity: v.quantity === null ? null : Number(v.quantity.toFixed(6)),
        quantityMax: v.quantityMax,
        unit: v.unit,
        unitRaw: v.unitRaw,
        item: v.item,
        note: v.note,
        confidence: v.confidence,
      });
    });
  }
});

describe("quantity vectors", () => {
  for (const [q, s] of quantity.format as Array<[number, string]>) {
    it(`format ${q}`, () => expect(formatQuantity(q)).toBe(s));
  }
  for (const v of quantity.convert) {
    it(`convert ${v.quantity} ${v.unit} → ${v.system}`, () =>
      expect(convertQuantity(v.quantity, v.max, v.unit, v.system as UnitSystem)).toEqual(v.expect));
  }
});

describe("link vectors", () => {
  for (const v of links) {
    it(v.input, () => {
      const c = classifyLink(v.input);
      if (v.platform === null) expect(c).toBeNull();
      else expect(c).toEqual({ platform: v.platform, canonicalUrl: v.canonicalUrl, creatorHandle: v.creatorHandle, postId: v.postId, isShortLink: v.isShortLink });
    });
  }
});

describe("text vectors", () => {
  for (const v of text) {
    it(v.name, () => {
      const d = structureText(v.text, v.provenance as Provenance);
      expect({
        title: d.title,
        servings: d.servings,
        prepMinutes: d.prepMinutes,
        cookMinutes: d.cookMinutes,
        totalMinutes: d.totalMinutes,
        ingredientCount: d.ingredients.length,
        steps: d.steps.map((s) => s.text),
      }).toEqual(v.expect);
    });
  }
});
