import type { InputLine } from "@larder/parser";

export function visionConfigured(): boolean {
  return Boolean(process.env.GOOGLE_VISION_API_KEY);
}

interface Vertex { x?: number; y?: number }
interface VSymbol { text?: string; property?: { detectedBreak?: { type?: string } } }
interface VWord { symbols?: VSymbol[]; confidence?: number; boundingBox?: { vertices?: Vertex[] } }
interface VPage { width?: number; height?: number; blocks?: { paragraphs?: { words?: VWord[] }[] }[] }
export interface VisionResponse { responses?: { fullTextAnnotation?: { pages?: VPage[] }; error?: { message?: string } }[] }

/** Rebuilds text lines (with confidence and a normalized box) from a DOCUMENT_TEXT_DETECTION response. */
export function visionToLines(res: VisionResponse, pageIndex: number): InputLine[] {
  const out: InputLine[] = [];
  const page = res.responses?.[0]?.fullTextAnnotation?.pages?.[0];
  if (!page) return out;
  const W = page.width || 1;
  const H = page.height || 1;
  let text = "";
  let confs: number[] = [];
  let xs: number[] = [];
  let ys: number[] = [];
  const flush = () => {
    const t = text.trim();
    if (t) {
      const minX = Math.min(...xs), maxX = Math.max(...xs), minY = Math.min(...ys), maxY = Math.max(...ys);
      out.push({
        text: t,
        confidence: confs.length ? confs.reduce((a, b) => a + b, 0) / confs.length : null,
        box: xs.length ? { page: pageIndex, x: minX / W, y: minY / H, w: (maxX - minX) / W, h: (maxY - minY) / H } : null,
      });
    }
    text = "";
    confs = [];
    xs = [];
    ys = [];
  };
  for (const block of page.blocks ?? []) {
    for (const para of block.paragraphs ?? []) {
      for (const word of para.words ?? []) {
        if (typeof word.confidence === "number") confs.push(word.confidence);
        for (const v of word.boundingBox?.vertices ?? []) {
          xs.push(v.x ?? 0);
          ys.push(v.y ?? 0);
        }
        for (const s of word.symbols ?? []) {
          text += s.text ?? "";
          const br = s.property?.detectedBreak?.type;
          if (br === "SPACE" || br === "SURE_SPACE") text += " ";
          else if (br === "EOL_SURE_SPACE" || br === "LINE_BREAK") flush();
          else if (br === "HYPHEN") text += "";
        }
      }
      flush();
    }
  }
  return out;
}

/** Cloud OCR (Google Cloud Vision) for one page; only called after the user opts in. */
export async function ocrPage(base64: string, pageIndex: number): Promise<InputLine[]> {
  const res = await fetch(`https://vision.googleapis.com/v1/images:annotate`, {
    method: "POST",
    signal: AbortSignal.timeout(20_000),
    headers: { "content-type": "application/json", "x-goog-api-key": process.env.GOOGLE_VISION_API_KEY! },
    body: JSON.stringify({ requests: [{ image: { content: base64 }, features: [{ type: "DOCUMENT_TEXT_DETECTION" }] }] }),
  });
  if (!res.ok) throw new Error(`Vision request failed: ${res.status}`);
  const data = (await res.json()) as VisionResponse;
  const err = data.responses?.[0]?.error?.message;
  if (err) throw new Error(`Vision error: ${err}`);
  return visionToLines(data, pageIndex);
}
