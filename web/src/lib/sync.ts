import type { Recipe, SyncResponse } from "@larder/parser";
import { collections, fromDoc, toDoc } from "./db";

type Versioned = { id: string; version: number; updatedAt: string };

/** Last writer wins: higher version, then later updatedAt. Ties keep the server copy. */
export function incomingWins(incoming: Versioned, existing: Versioned | null): boolean {
  if (!existing) return true;
  if (incoming.version !== existing.version) return incoming.version > existing.version;
  return incoming.updatedAt > existing.updatedAt;
}

async function insertIfAbsent(insert: () => Promise<unknown>): Promise<boolean> {
  try {
    await insert();
    return true;
  } catch (err) {
    if ((err as { code?: number }).code === 11000) return false;
    throw err;
  }
}

export async function runSync(ownerId: string, req: { cursor: string | null; recipes: Recipe[] }, now = new Date()): Promise<SyncResponse> {
  const { recipes } = await collections();
  const conflicts: SyncResponse["conflicts"] = [];
  const serverTime = now.toISOString();

  for (const incoming of req.recipes) {
    const existing = await recipes.findOne({ _id: incoming.id });
    if (existing && existing.ownerId !== ownerId) {
      conflicts.push({ id: incoming.id });
      continue;
    }
    if (!incomingWins(incoming, existing ? fromDoc<Recipe>(existing) : null)) {
      conflicts.push({ id: incoming.id });
      continue;
    }
    const doc = toDoc({ ...incoming, ownerId, updatedAt: serverTime });
    // Conditional on the copy we compared against, so a concurrent sync can't be overwritten.
    const written = existing
      ? (await recipes.replaceOne({ _id: doc._id, ownerId, version: existing.version, updatedAt: existing.updatedAt }, doc)).matchedCount === 1
      : await insertIfAbsent(() => recipes.insertOne(doc));
    if (!written) conflicts.push({ id: incoming.id });
  }

  const since = req.cursor ?? new Date(0).toISOString();
  const changed = await recipes.find({ ownerId, updatedAt: { $gt: since } }).toArray();
  return { cursor: serverTime, recipes: changed.map((d) => fromDoc<Recipe>(d)), conflicts };
}

export async function allRecipes(ownerId: string): Promise<Recipe[]> {
  const { recipes } = await collections();
  const docs = await recipes.find({ ownerId, deleted: false }).sort({ title: 1 }).toArray();
  return docs.map((d) => fromDoc<Recipe>(d));
}
