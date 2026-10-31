import { MongoMemoryServer } from "mongodb-memory-server";
import { MongoClient } from "mongodb";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import type { Recipe } from "@larder/parser";
import { setClientForTesting } from "./db";
import { setFetcherForTesting } from "./link-import";
import type { FetchedPage, Fetcher } from "./safe-fetch";
import { POST as linkPOST } from "@/app/api/v1/imports/link/route";
import { POST as textPOST } from "@/app/api/v1/imports/text/route";
import { POST as syncPOST } from "@/app/api/v1/sync/route";
import { GET as exportGET } from "@/app/api/v1/export/route";
import { GET as meGET, PUT as mePUT } from "@/app/api/v1/me/route";

let mongod: MongoMemoryServer;
let client: MongoClient;
let fetched: string[] = [];

const recipePage = `<html><script type="application/ld+json">{"@type":"Recipe","name":"Nonna's Pasta","author":{"name":"Nonna"},
"recipeIngredient":["200 g spaghetti","3 cloves garlic"],"recipeInstructions":["Boil pasta.","Toss with garlic."]}</script></html>`;

const pages: Record<string, FetchedPage> = {
  "https://www.tiktok.com/oembed?url=https%3A%2F%2Fwww.tiktok.com%2F%40nonna%2Fvideo%2F123": {
    status: 200, finalUrl: "", contentType: "application/json",
    body: JSON.stringify({ title: "Garlic pasta 🍝 full recipe: https://blog.test/pasta #pasta", author_name: "Nonna Pia", author_unique_id: "nonna", thumbnail_url: "https://p.test/t.jpg" }),
  },
  "https://www.tiktok.com/oembed?url=https%3A%2F%2Fwww.tiktok.com%2F%40chef%2Fvideo%2F456": {
    status: 200, finalUrl: "", contentType: "application/json",
    body: JSON.stringify({ title: "Quick eggs\n2 eggs\n1 tbsp butter\nMelt butter and scramble the eggs.", author_name: "Chef", author_unique_id: "chef" }),
  },
  "https://www.tiktok.com/oembed?url=https%3A%2F%2Fwww.tiktok.com%2F%40gone%2Fvideo%2F789": { status: 400, finalUrl: "", contentType: "application/json", body: "{}" },
  "https://blog.test/pasta": { status: 200, finalUrl: "https://blog.test/pasta", contentType: "text/html", body: recipePage },
};

const fakeFetch: Fetcher = async (url) => {
  fetched.push(url);
  const page = pages[url];
  if (!page) return { status: 404, finalUrl: url, contentType: "text/html", body: "" };
  return { ...page, finalUrl: page.finalUrl || url };
};

beforeAll(async () => {
  mongod = await MongoMemoryServer.create();
  client = new MongoClient(mongod.getUri());
  setClientForTesting(client);
  setFetcherForTesting(fakeFetch);
  process.env.MONGODB_URI = mongod.getUri();
  process.env.AUTH_DEV_BYPASS = "1";
});

afterAll(async () => {
  setClientForTesting(null);
  setFetcherForTesting(null);
  await client.close();
  await mongod.stop();
});

beforeEach(() => {
  fetched = [];
});

const ctx = {} as never;

function req(path: string, uid: string | null, body?: unknown, method?: string): Request {
  return new Request(`http://localhost${path}`, {
    method: method ?? (body === undefined ? "GET" : "POST"),
    headers: { ...(uid ? { authorization: `Bearer dev:${uid}` } : {}), "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

function recipe(id: string, version: number, title: string): Recipe {
  return {
    id, ownerId: "x", status: "saved", title, servings: 2, yieldText: "Serves 2", prepMinutes: null, cookMinutes: 10, totalMinutes: null,
    ingredients: [{ id: "i1", raw: "2 eggs", isSection: false, quantity: 2, quantityMax: null, unit: null, unitRaw: null, item: "eggs", note: null, confidence: "high", provenance: "manual" }],
    steps: [{ id: "s1", text: "Scramble <gently>.", confidence: "high", provenance: "manual" }],
    fieldConfidence: { title: "high", servings: "high", times: "high" }, foundIn: ["manual"],
    source: { kind: "tiktok", url: "https://www.tiktok.com/@chef/video/456", creatorHandle: "@chef", creatorName: null, scanType: null, pageCount: 0, retrievedAt: null },
    notes: "", tags: ["breakfast"], imageKeys: [], thumbnailUrl: null, wantToCook: false,
    createdAt: "2026-10-20T10:00:00.000Z", updatedAt: "2026-10-20T10:00:00.000Z", version, deleted: false,
  };
}

describe("imports/link", () => {
  it("requires auth and a link", async () => {
    expect((await linkPOST(req("/api/v1/imports/link", null, { url: "https://x.test/a" }), ctx)).status).toBe(401);
    expect((await linkPOST(req("/api/v1/imports/link", "alice", { url: "hello there" }), ctx)).status).toBe(400);
  });

  it("follows a TikTok caption to the linked recipe page and keeps attribution", async () => {
    const res = await linkPOST(req("/api/v1/imports/link", "alice", { url: "https://www.tiktok.com/@nonna/video/123?is_from_webapp=1" }), ctx);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.receipt).toMatchObject({ platform: "tiktok", creatorHandle: "@nonna", creatorName: "Nonna Pia", canonicalUrl: "https://www.tiktok.com/@nonna/video/123" });
    expect(body.draft.title).toBe("Nonna's Pasta");
    expect(body.draft.ingredients).toHaveLength(2);
    expect(body.draft.foundIn).toEqual(["linked_page"]);
    expect(body.needsUserText).toBe(false);
    expect(body.layers.find((l: { name: string }) => l.name === "linked_page").status).toBe("ok");
  });

  it("serves repeat imports from the per-URL cache", async () => {
    await linkPOST(req("/api/v1/imports/link", "bob", { url: "https://www.tiktok.com/@nonna/video/123" }), ctx);
    expect(fetched).toEqual([]);
  });

  it("parses a recipe in the caption itself", async () => {
    const body = await (await linkPOST(req("/api/v1/imports/link", "alice", { url: "https://www.tiktok.com/@chef/video/456" }), ctx)).json();
    expect(body.draft.title).toBe("Quick eggs");
    expect(body.draft.ingredients.map((i: { item: string }) => i.item)).toEqual(["eggs", "butter"]);
    expect(body.draft.foundIn).toEqual(["caption"]);
  });

  it("is honest when Instagram can't be read", async () => {
    const body = await (await linkPOST(req("/api/v1/imports/link", "alice", { url: "https://www.instagram.com/reel/Cabc/" }), ctx)).json();
    expect(body.draft).toBeNull();
    expect(body.needsUserText).toBe(true);
    expect(body.message).toMatch(/Paste the caption or add a screenshot/);
    expect(fetched).toEqual([]);
  });

  it("reports unavailable TikTok posts", async () => {
    const body = await (await linkPOST(req("/api/v1/imports/link", "alice", { url: "https://www.tiktok.com/@gone/video/789" }), ctx)).json();
    expect(body.classification).toBe("unavailable");
  });

  it("counts social imports against the monthly allowance", async () => {
    const me = await (await meGET(req("/api/v1/me", "alice"), ctx)).json();
    expect(me.importsThisMonth).toBe(2);
  });
});

describe("imports/text", () => {
  it("structures pasted caption text without AI", async () => {
    const res = await textPOST(req("/api/v1/imports/text", "alice", { text: "Toast\n2 slices bread\nToast the bread." }), ctx);
    const body = await res.json();
    expect(body.draft.ingredients[0]).toMatchObject({ quantity: 2, unit: "slice", item: "bread", provenance: "pasted_text" });
    expect(body.draft.steps[0].text).toBe("Toast the bread.");
  });

  it("rejects empty text and unavailable AI", async () => {
    expect((await textPOST(req("/api/v1/imports/text", "alice", { text: "  " }), ctx)).status).toBe(400);
    expect((await textPOST(req("/api/v1/imports/text", "alice", { text: "2 eggs", ai: true }), ctx)).status).toBe(503);
  });
});

describe("sync, export, me", () => {
  it("syncs with last-writer-wins and isolates owners", async () => {
    let body = await (await syncPOST(req("/api/v1/sync", "alice", { cursor: null, recipes: [recipe("r1", 1, "Eggs")] }), ctx)).json();
    expect(body.conflicts).toEqual([]);
    expect(body.recipes.map((r: Recipe) => [r.id, r.ownerId])).toEqual([["r1", "alice"]]);

    body = await (await syncPOST(req("/api/v1/sync", "alice", { cursor: null, recipes: [recipe("r1", 0, "Old")] }), ctx)).json();
    expect(body.conflicts).toEqual([{ id: "r1" }]);

    body = await (await syncPOST(req("/api/v1/sync", "mallory", { cursor: null, recipes: [recipe("r1", 9, "Mine now")] }), ctx)).json();
    expect(body.conflicts).toEqual([{ id: "r1" }]);
    expect(body.recipes).toEqual([]);
  });

  it("exports JSON and escaped HTML", async () => {
    const jsonBody = await (await exportGET(req("/api/v1/export", "alice"), ctx)).json();
    expect(jsonBody.recipes.map((r: Recipe) => r.title)).toEqual(["Eggs"]);
    const html = await (await exportGET(req("/api/v1/export?format=html", "alice"), ctx)).text();
    expect(html).toContain("Scramble &lt;gently&gt;.");
    expect(html).toContain('href="https://www.tiktok.com/@chef/video/456"');
    expect((await exportGET(req("/api/v1/export?format=pdf", "alice"), ctx)).status).toBe(400);
  });

  it("updates profile settings", async () => {
    const body = await (await mePUT(req("/api/v1/me", "alice", { clipboardBanner: false }, "PUT"), ctx)).json();
    expect(body.clipboardBanner).toBe(false);
  });
});
