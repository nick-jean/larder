import { describe, expect, it } from "vitest";
import { parseModelOutput } from "./ai";
import { isPrivateAddress, safeFetch } from "./safe-fetch";
import { visionToLines } from "./vision";

describe("isPrivateAddress", () => {
  it.each([
    ["127.0.0.1", true], ["10.1.2.3", true], ["172.20.0.1", true], ["192.168.1.1", true], ["169.254.169.254", true],
    ["100.64.0.1", true], ["::1", true], ["fd00::1", true], ["::ffff:10.0.0.1", true], ["8.8.8.8", false], ["2606:4700::1111", false],
    ["::ffff:7f00:1", true],
    ["::ffff:5db8:d822", false],
  ])("%s → %s", (ip, expected) => expect(isPrivateAddress(ip)).toBe(expected));
});

describe("safeFetch", () => {
  it("refuses internal targets before connecting", async () => {
    await expect(safeFetch("http://127.0.0.1/admin")).rejects.toThrow(/Private/);
    await expect(safeFetch("http://localhost:3000/")).rejects.toThrow();
    await expect(safeFetch("http://169.254.169.254/latest/meta-data")).rejects.toThrow(/Private/);
    await expect(safeFetch("file:///etc/passwd")).rejects.toThrow(/http/);
  });
});

describe("parseModelOutput", () => {
  it("grounds model output in the source text", () => {
    const source = "Pancakes\n1 cup flour\nmilk\nMix and fry.";
    const d = parseModelOutput(
      JSON.stringify({ title: "Pancakes", servings: 4, ingredients: ["1 cup flour", "1 cup milk"], steps: ["Mix and fry."] }),
      source,
    )!;
    expect(d.ingredients[0]).toMatchObject({ quantity: 1, unit: "cup", provenance: "llm" });
    // "1" is in the source, but not on the milk line, so the quantity is dropped.
    expect(d.ingredients[1]).toMatchObject({ quantity: null, confidence: "low" });
    expect(d.servings).toBeNull();
    expect(parseModelOutput("not json", source)).toBeNull();
  });
});

describe("visionToLines", () => {
  it("rebuilds lines with confidence and normalized boxes", () => {
    const sym = (t: string, br?: string) => ({ text: t, ...(br ? { property: { detectedBreak: { type: br } } } : {}) });
    const lines = visionToLines(
      {
        responses: [{
          fullTextAnnotation: {
            pages: [{
              width: 100, height: 200,
              blocks: [{ paragraphs: [{ words: [
                { confidence: 0.9, symbols: [sym("2", "SPACE")], boundingBox: { vertices: [{ x: 10, y: 20 }, { x: 20, y: 40 }] } },
                { confidence: 0.7, symbols: [sym("c"), sym("u"), sym("p", "SPACE")], boundingBox: { vertices: [{ x: 22, y: 20 }, { x: 50, y: 40 }] } },
                { confidence: 0.8, symbols: [sym("f"), sym("l"), sym("o"), sym("u"), sym("r", "LINE_BREAK")], boundingBox: { vertices: [{ x: 52, y: 20 }, { x: 90, y: 40 }] } },
              ] }] }],
            }],
          },
        }],
      },
      1,
    );
    expect(lines).toHaveLength(1);
    expect(lines[0].text).toBe("2 cup flour");
    expect(lines[0].confidence).toBeCloseTo(0.8);
    expect(lines[0].box).toEqual({ page: 1, x: 0.1, y: 0.1, w: 0.8, h: 0.1 });
  });
});
