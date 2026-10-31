import { attachDatabasePool } from "@vercel/functions";
import { MongoClient, type Db } from "mongodb";
import type { ImportResult, Recipe, UserProfile } from "@larder/parser";

type Doc<T> = Omit<T, "id"> & { _id: string };

export interface RateLimitDoc {
  _id: string;
  count: number;
  expiresAt: Date;
}

/** Per-URL cache of link imports (public data only), keyed by canonical URL. */
export interface LinkCacheDoc {
  _id: string;
  result: Omit<ImportResult, "importId">;
  expiresAt: Date;
}

/** Import log: what was imported, by whom, how (no recipe text). */
export interface ImportDoc {
  _id: string;
  ownerId: string;
  kind: "link" | "text" | "image";
  platform: string | null;
  url: string | null;
  layers: string[];
  ai: boolean;
  createdAt: string;
}

let client: MongoClient | null = null;
let indexesReady: Promise<void> | null = null;

export function hasDatabase(): boolean {
  return Boolean(process.env.MONGODB_URI);
}

export function getClient(): MongoClient {
  const uri = process.env.MONGODB_URI;
  if (!uri) throw new Error("MONGODB_URI is not configured");
  if (!client) {
    client = new MongoClient(uri, { maxPoolSize: 5, maxIdleTimeMS: 5_000 });
    attachDatabasePool(client);
  }
  return client;
}

/** For tests: inject a client (e.g. mongodb-memory-server) and reset index state. */
export function setClientForTesting(c: MongoClient | null): void {
  client = c;
  indexesReady = null;
}

export async function getDb(): Promise<Db> {
  const db = getClient().db(process.env.MONGODB_DB ?? "larder");
  indexesReady ??= ensureIndexes(db).catch((err: unknown) => {
    indexesReady = null;
    throw err;
  });
  await indexesReady;
  return db;
}

async function ensureIndexes(db: Db): Promise<void> {
  await Promise.all([
    db.collection("recipes").createIndex({ ownerId: 1, updatedAt: 1 }),
    db.collection("imports").createIndex({ ownerId: 1, createdAt: -1 }),
    db.collection("link_cache").createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 }),
    db.collection("rate_limits").createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 }),
  ]);
}

export async function collections() {
  const db = await getDb();
  return {
    users: db.collection<Doc<UserProfile>>("users"),
    recipes: db.collection<Doc<Recipe>>("recipes"),
    imports: db.collection<ImportDoc>("imports"),
    linkCache: db.collection<LinkCacheDoc>("link_cache"),
    rateLimits: db.collection<RateLimitDoc>("rate_limits"),
  };
}

export function toDoc<T extends { id: string }>(value: T): Doc<T> {
  const { id, ...rest } = value;
  return { _id: id, ...rest };
}

export function fromDoc<T extends { id: string }>(doc: Doc<T>): T {
  const { _id, ...rest } = doc;
  return { id: _id, ...rest } as unknown as T;
}
