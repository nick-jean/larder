import { SyncRequest } from "@larder/parser";
import { authed, json, parseBody, requireDatabase } from "@/lib/http";
import { runSync } from "@/lib/sync";

export const POST = authed(async (request, user) => {
  requireDatabase();
  const body = await parseBody(request, SyncRequest);
  return json(await runSync(user.uid, body));
});
