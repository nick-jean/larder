import { connection } from "next/server";
import { aiConfigured } from "@/lib/ai";
import { hasDatabase } from "@/lib/db";
import { visionConfigured } from "@/lib/vision";

export async function GET() {
  await connection();
  return Response.json({
    ok: true,
    database: hasDatabase(),
    auth: Boolean(process.env.FIREBASE_PROJECT_ID),
    metaOembed: Boolean(process.env.META_OEMBED_TOKEN),
    ai: aiConfigured(),
    cloudOcr: visionConfigured(),
  });
}
