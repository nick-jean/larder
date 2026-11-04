import { collections } from "./db";
import { HttpError } from "./http";

export interface RateLimit {
  /** Counter name; also used in the key, so keep it stable. */
  name: string;
  max: number;
  windowMs: number;
  /** Error shown to the client when exceeded. */
  message: string;
}

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;

function envInt(name: string, fallback: number): number {
  const v = Number.parseInt(process.env[name] ?? "", 10);
  return Number.isFinite(v) && v >= 0 ? v : fallback;
}

export function linkImportLimits(): RateLimit[] {
  return [
    { name: "link-minute", max: envInt("LINK_IMPORT_PER_MINUTE", 20), windowMs: MINUTE, message: "Too many imports. Try again in a minute." },
    { name: "link-day", max: envInt("LINK_IMPORT_PER_DAY", 300), windowMs: DAY, message: "Daily import limit reached." },
  ];
}

/** Per-account limits on paid cloud calls (OCR and LLM structuring), plus a global daily cost ceiling. */
export function paidLimits(kind: "ocr" | "ai"): { account: RateLimit[]; global: RateLimit[] } {
  const KIND = kind.toUpperCase();
  const what = kind === "ocr" ? "cloud reads" : "AI tidy-ups";
  return {
    account: [
      { name: `${kind}-minute`, max: envInt(`${KIND}_PER_MINUTE`, 5), windowMs: MINUTE, message: `Too many ${what}. Try again in a minute.` },
      { name: `${kind}-day`, max: envInt(`${KIND}_PER_DAY`, 30), windowMs: DAY, message: `Daily limit for ${what} reached. The on-device result is still yours to edit.` },
    ],
    global: [
      { name: `${kind}-global-day`, max: envInt(`${KIND}_GLOBAL_PER_DAY`, 5_000), windowMs: DAY, message: `${what[0].toUpperCase()}${what.slice(1)} are temporarily unavailable.` },
    ],
  };
}

/**
 * Fixed-window counters in MongoDB (works across serverless instances). Each call counts one
 * request against every limit and throws 429 with Retry-After when any is exceeded.
 */
export async function consumeRateLimits(subject: string, limits: RateLimit[], now = new Date()): Promise<void> {
  const { rateLimits } = await collections();
  for (const limit of limits) {
    const windowStart = Math.floor(now.getTime() / limit.windowMs) * limit.windowMs;
    const _id = `${limit.name}:${subject}:${windowStart}`;
    const expiresAt = new Date(windowStart + limit.windowMs);
    let count = 0;
    for (let attempt = 0; ; attempt++) {
      try {
        const doc = await rateLimits.findOneAndUpdate(
          { _id },
          { $inc: { count: 1 }, $setOnInsert: { expiresAt } },
          { upsert: true, returnDocument: "after" },
        );
        count = doc?.count ?? 1;
        break;
      } catch (err) {
        // Concurrent upserts of a new window can race on _id; the retry finds the inserted doc.
        if ((err as { code?: number }).code !== 11000 || attempt > 0) throw err;
      }
    }
    if (count > limit.max) {
      const retryAfter = Math.max(1, Math.ceil((expiresAt.getTime() - now.getTime()) / 1000));
      throw new HttpError(429, limit.message, { limit: limit.name, retryAfterSeconds: retryAfter }, { "retry-after": String(retryAfter) });
    }
  }
}
