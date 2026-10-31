import { describe, expect, it } from "vitest";
import { extractJsonLdRecipe, groundDraft, parseIsoDuration, structureLines, structureText } from "./index";

const html = `<html><head><meta property="og:site_name" content="Sally&#39;s Kitchen">
<script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"WebPage"},{"@type":["Recipe"],"name":"Best Chili &amp; Cornbread","author":[{"@type":"Person","name":"Sally"}],"image":["https://x.test/a.jpg"],"recipeYield":["6","6 bowls"],"prepTime":"PT15M","cookTime":"PT1H","totalTime":"PT1H15M","recipeIngredient":["2 lb ground beef","1 (15 oz) can beans","2 tbsp chili powder"],"recipeInstructions":[{"@type":"HowToSection","name":"Chili","itemListElement":[{"@type":"HowToStep","text":"Brown the beef."},{"@type":"HowToStep","text":"Add beans and simmer."}]}]}]}</script></head></html>`;

describe("extractJsonLdRecipe", () => {
  it("reads a Recipe nested in @graph", () => {
    const r = extractJsonLdRecipe(html)!;
    expect(r.draft.title).toBe("Best Chili & Cornbread");
    expect(r.author).toBe("Sally");
    expect(r.siteName).toBe("Sally's Kitchen");
    expect(r.imageUrl).toBe("https://x.test/a.jpg");
    expect(r.draft.servings).toBe(6);
    expect(r.draft.yieldText).toBe("6 bowls");
    expect([r.draft.prepMinutes, r.draft.cookMinutes, r.draft.totalMinutes]).toEqual([15, 60, 75]);
    expect(r.draft.ingredients.map((i) => [i.quantity, i.unit, i.item])).toEqual([
      [2, "lb", "ground beef"],
      [1, "can", "beans"],
      [2, "tbsp", "chili powder"],
    ]);
    expect(r.draft.steps.map((s) => s.text)).toEqual(["Brown the beef.", "Add beans and simmer."]);
    expect(r.draft.foundIn).toEqual(["linked_page"]);
  });
  it("returns null without Recipe markup or with broken JSON", () => {
    expect(extractJsonLdRecipe("<script type=application/ld+json>{oops</script>")).toBeNull();
    expect(extractJsonLdRecipe('<script type="application/ld+json">{"@type":"Article"}</script>')).toBeNull();
  });
  it("parses ISO durations", () => {
    expect(parseIsoDuration("PT1H30M")).toBe(90);
    expect(parseIsoDuration("P0DT0H45M")).toBe(45);
    expect(parseIsoDuration("PT")).toBeNull();
    expect(parseIsoDuration(45)).toBeNull();
  });
});

describe("structureLines with OCR input", () => {
  it("carries OCR confidence and flags page seams", () => {
    const d = structureLines(
      [
        { text: "Grandma's Biscuits", confidence: 0.95, box: { page: 0, x: 0, y: 0, w: 1, h: 0.1 } },
        { text: "2 cups flour", confidence: 0.5, box: { page: 0, x: 0, y: 0.2, w: 1, h: 0.05 } },
        { text: "Mix the flour with cold butter until", confidence: 0.9, box: { page: 0, x: 0, y: 0.8, w: 1, h: 0.05 } },
        { text: "crumbly.", confidence: 0.9, box: { page: 1, x: 0, y: 0, w: 1, h: 0.05 } },
      ],
      "ocr",
    );
    expect(d.title).toBe("Grandma's Biscuits");
    expect(d.ingredients[0].confidence).toBe("low");
    expect(d.steps).toHaveLength(1);
    expect(d.steps[0].text).toBe("Mix the flour with cold butter until crumbly.");
    expect(d.steps[0].seam).toBe(true);
    expect(d.steps[0].confidence).toBe("medium");
  });
});

describe("groundDraft", () => {
  it("drops quantities the source never mentions", () => {
    const source = "Pancakes\n1 cup flour\nsome milk\nMix and fry.";
    const draft = structureText(source, "caption");
    draft.ingredients[1] = { ...draft.ingredients[1], quantity: 2, unit: "cup" };
    draft.servings = 4;
    const g = groundDraft(draft, source);
    expect(g.ingredients[0].quantity).toBe(1);
    expect(g.ingredients[1].quantity).toBeNull();
    expect(g.ingredients[1].confidence).toBe("low");
    expect(g.servings).toBeNull();
    expect(g.foundIn).toContain("llm");
  });

  it("keeps quantities of ingredients wrapped across OCR lines", () => {
    const source = "Bread\n3 cups\nbread flour\nMix and bake.";
    const draft = structureText("Bread\n3 cups bread flour\nMix and bake.", "llm");
    expect(groundDraft(draft, source).ingredients[0]).toMatchObject({ quantity: 3, item: "bread flour" });
  });
});
