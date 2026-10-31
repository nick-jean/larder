import type { UserProfile } from "@larder/parser";
import type { AuthUser } from "./auth";
import { collections, fromDoc } from "./db";

/** Free tier: unlimited manual and web saves, plus this many social/cloud-OCR/AI imports a month. */
export const FREE_IMPORTS_PER_MONTH = 20;

export function monthKey(date = new Date()): string {
  return date.toISOString().slice(0, 7);
}

export async function getOrCreateUser(user: AuthUser): Promise<UserProfile> {
  const { users } = await collections();
  const now = new Date().toISOString();
  const doc = await users.findOneAndUpdate(
    { _id: user.uid },
    {
      $setOnInsert: {
        displayName: user.name ?? user.email?.split("@")[0] ?? "Cook",
        plan: "free",
        importsThisMonth: 0,
        importMonth: monthKey(),
        clipboardBanner: true,
        updatedAt: now,
      },
    },
    { upsert: true, returnDocument: "after" },
  );
  return fromDoc<UserProfile>(doc!);
}

/** Atomically consumes one import from the monthly allowance. Returns false when exhausted. */
export async function consumeImport(uid: string, now = new Date()): Promise<boolean> {
  const { users } = await collections();
  const month = monthKey(now);
  await users.updateOne({ _id: uid, importMonth: { $ne: month } }, { $set: { importMonth: month, importsThisMonth: 0 } });
  const res = await users.updateOne(
    { _id: uid, $or: [{ plan: "plus" }, { importsThisMonth: { $lt: FREE_IMPORTS_PER_MONTH } }] },
    { $inc: { importsThisMonth: 1 }, $set: { updatedAt: now.toISOString() } },
  );
  return res.modifiedCount === 1;
}

/** Gives back an allowance unit when the paid call failed. */
export async function refundImport(uid: string): Promise<void> {
  const { users } = await collections();
  await users.updateOne({ _id: uid, importsThisMonth: { $gt: 0 } }, { $inc: { importsThisMonth: -1 } });
}
