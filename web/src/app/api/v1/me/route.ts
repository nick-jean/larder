import { UpdateProfileRequest, type UserProfile } from "@larder/parser";
import { collections, fromDoc } from "@/lib/db";
import { authed, json, parseBody, requireDatabase } from "@/lib/http";
import { getOrCreateUser } from "@/lib/users";

export const GET = authed(async (_request, user) => {
  requireDatabase();
  return json(await getOrCreateUser(user));
});

export const PUT = authed(async (request, user) => {
  requireDatabase();
  const update = await parseBody(request, UpdateProfileRequest);
  await getOrCreateUser(user);
  const { users } = await collections();
  const doc = await users.findOneAndUpdate(
    { _id: user.uid },
    { $set: { ...update, updatedAt: new Date().toISOString() } },
    { returnDocument: "after" },
  );
  return json(fromDoc<UserProfile>(doc!));
});
