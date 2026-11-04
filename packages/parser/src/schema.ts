import { z } from "zod";

export const Confidence = z.enum(["high", "medium", "low"]);
export type Confidence = z.infer<typeof Confidence>;

/** Where a field came from, shown in the provenance strip. */
export const Provenance = z.enum(["caption", "linked_page", "ocr", "pasted_text", "llm", "manual"]);
export type Provenance = z.infer<typeof Provenance>;

export const Platform = z.enum(["tiktok", "instagram", "facebook", "web"]);
export type Platform = z.infer<typeof Platform>;

export const SourceKind = z.enum(["tiktok", "instagram", "facebook", "web", "scan", "manual"]);
export type SourceKind = z.infer<typeof SourceKind>;

export const ScanType = z.enum(["cookbook", "handwritten", "screenshot"]);
export type ScanType = z.infer<typeof ScanType>;

/** Normalised bounding box of a line in its source page image (0..1 fractions). */
export const Box = z.object({ page: z.number().int().min(0), x: z.number(), y: z.number(), w: z.number(), h: z.number() });
export type Box = z.infer<typeof Box>;

export const IngredientLine = z.object({
  id: z.string().min(1).max(64),
  raw: z.string().max(500),
  /** Section header ("For the sauce") rather than an ingredient. */
  isSection: z.boolean(),
  quantity: z.number().nullable(),
  /** Upper bound of a range ("2–3"). */
  quantityMax: z.number().nullable(),
  /** Canonical unit key (see UNITS), or null. */
  unit: z.string().max(20).nullable(),
  /** Unit exactly as written, kept for display. */
  unitRaw: z.string().max(40).nullable(),
  item: z.string().max(500),
  note: z.string().max(500).nullable(),
  confidence: Confidence,
  provenance: Provenance,
  box: Box.nullable().optional(),
  /** Other plausible readings (e.g. "¼ cup" vs "¾ cup"), best first. */
  alternatives: z.array(z.string().max(500)).max(5).optional(),
});
export type IngredientLine = z.infer<typeof IngredientLine>;

export const StepLine = z.object({
  id: z.string().min(1).max(64),
  text: z.string().max(4000),
  confidence: Confidence,
  provenance: Provenance,
  box: Box.nullable().optional(),
  /** True when the step was joined across a page break and should be checked. */
  seam: z.boolean().optional(),
});
export type StepLine = z.infer<typeof StepLine>;

export const RecipeSource = z.object({
  kind: SourceKind,
  url: z.string().max(2000).nullable(),
  creatorHandle: z.string().max(200).nullable(),
  creatorName: z.string().max(200).nullable(),
  scanType: ScanType.nullable(),
  pageCount: z.number().int().min(0).max(50),
  retrievedAt: z.string().nullable(),
});
export type RecipeSource = z.infer<typeof RecipeSource>;

export const FieldConfidence = z.object({ title: Confidence, servings: Confidence, times: Confidence });
export type FieldConfidence = z.infer<typeof FieldConfidence>;

/** The parsed, not-yet-saved part of a recipe. */
export const RecipeDraft = z.object({
  title: z.string().max(300),
  servings: z.number().nullable(),
  yieldText: z.string().max(100).nullable(),
  prepMinutes: z.number().int().nullable(),
  cookMinutes: z.number().int().nullable(),
  totalMinutes: z.number().int().nullable(),
  ingredients: z.array(IngredientLine).max(300),
  steps: z.array(StepLine).max(300),
  fieldConfidence: FieldConfidence,
  /** Which provenances contributed, for the "Found in" strip. */
  foundIn: z.array(Provenance),
});
export type RecipeDraft = z.infer<typeof RecipeDraft>;

export const RecipeStatus = z.enum(["review", "saved"]);
export type RecipeStatus = z.infer<typeof RecipeStatus>;

export const Recipe = RecipeDraft.extend({
  id: z.string().min(1).max(64),
  ownerId: z.string().max(128),
  status: RecipeStatus,
  source: RecipeSource,
  notes: z.string().max(20_000),
  tags: z.array(z.string().max(60)).max(50),
  /** Local file names of original photos (device-only for now). */
  imageKeys: z.array(z.string().max(300)).max(50),
  thumbnailUrl: z.string().max(2000).nullable(),
  wantToCook: z.boolean(),
  createdAt: z.string(),
  updatedAt: z.string(),
  version: z.number().int().min(0),
  deleted: z.boolean(),
});
export type Recipe = z.infer<typeof Recipe>;

export const LayerName = z.enum(["resolve", "oembed", "linked_page", "caption", "user_text"]);
export type LayerName = z.infer<typeof LayerName>;

export const LayerStatus = z.enum(["ok", "none", "skipped", "error"]);
export type LayerStatus = z.infer<typeof LayerStatus>;

export const ImportLayer = z.object({ name: LayerName, status: LayerStatus, detail: z.string().nullable() });
export type ImportLayer = z.infer<typeof ImportLayer>;

export const LinkReceipt = z.object({
  platform: Platform,
  url: z.string(),
  canonicalUrl: z.string(),
  creatorHandle: z.string().nullable(),
  creatorName: z.string().nullable(),
  captionSnippet: z.string().nullable(),
  thumbnailUrl: z.string().nullable(),
});
export type LinkReceipt = z.infer<typeof LinkReceipt>;

export const ImportResult = z.object({
  importId: z.string(),
  receipt: LinkReceipt.nullable(),
  layers: z.array(ImportLayer),
  draft: RecipeDraft.nullable(),
  /** No usable recipe text was retrievable: ask for the caption or a screenshot. */
  needsUserText: z.boolean(),
  /** "recipe" | "not_recipe" | "unavailable" (dead or private link). */
  classification: z.enum(["recipe", "not_recipe", "unavailable"]),
  message: z.string().nullable(),
});
export type ImportResult = z.infer<typeof ImportResult>;

export const LinkImportRequest = z.object({ url: z.string().min(4).max(2000) });
export type LinkImportRequest = z.infer<typeof LinkImportRequest>;

export const OcrLineInput = z.object({
  text: z.string().max(1000),
  confidence: z.number().min(0).max(1).nullable().optional(),
  box: Box.nullable().optional(),
});
export type OcrLineInput = z.infer<typeof OcrLineInput>;

export const TextImportRequest = z
  .object({
    /** Pasted caption/recipe text; or OCR lines below. */
    text: z.string().max(20_000).optional(),
    lines: z.array(OcrLineInput).max(1500).optional(),
    provenance: z.enum(["pasted_text", "ocr"]).default("pasted_text"),
    /** The link the text belongs to, for attribution. */
    url: z.string().max(2000).optional(),
    /** Opt-in server LLM structuring (paid; rate limited). */
    ai: z.boolean().default(false),
  })
  .refine((v) => Boolean(v.text?.trim()) || (v.lines?.length ?? 0) > 0, { message: "text or lines is required" });
export type TextImportRequest = z.infer<typeof TextImportRequest>;

export const ImageImportRequest = z.object({
  /** Base64 JPEG/PNG pages, each already downscaled on device. */
  pages: z.array(z.string().max(4_000_000)).min(1).max(4),
  scanType: ScanType,
});
export type ImageImportRequest = z.infer<typeof ImageImportRequest>;

export const SyncRequest = z.object({
  cursor: z.string().nullable(),
  recipes: z.array(Recipe).max(500),
});
export type SyncRequest = z.infer<typeof SyncRequest>;

export const SyncResponse = z.object({
  cursor: z.string(),
  recipes: z.array(Recipe),
  conflicts: z.array(z.object({ id: z.string() })),
});
export type SyncResponse = z.infer<typeof SyncResponse>;

export const Plan = z.enum(["free", "plus"]);

export const UserProfile = z.object({
  id: z.string(),
  displayName: z.string().max(100),
  plan: Plan,
  importsThisMonth: z.number().int(),
  importMonth: z.string(),
  clipboardBanner: z.boolean(),
  updatedAt: z.string(),
});
export type UserProfile = z.infer<typeof UserProfile>;

export const UpdateProfileRequest = z.object({
  displayName: z.string().min(1).max(100).optional(),
  clipboardBanner: z.boolean().optional(),
});
