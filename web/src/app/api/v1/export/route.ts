import { libraryToHtml } from "@/lib/export";
import { authed, HttpError, json, requireDatabase } from "@/lib/http";
import { allRecipes } from "@/lib/sync";

/** Full library export: ?format=json (default) or html. */
export const GET = authed(async (request, user) => {
  requireDatabase();
  const format = new URL(request.url).searchParams.get("format") ?? "json";
  const recipes = await allRecipes(user.uid);
  const exportedAt = new Date().toISOString();
  const stamp = exportedAt.slice(0, 10);
  if (format === "json") {
    return json({ format: "larder-export", version: 1, exportedAt, recipes }, 200, {
      "content-disposition": `attachment; filename="larder-${stamp}.json"`,
    });
  }
  if (format === "html") {
    return new Response(libraryToHtml(recipes, exportedAt), {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
        "content-disposition": `attachment; filename="larder-${stamp}.html"`,
      },
    });
  }
  throw new HttpError(400, "format must be json or html");
});
