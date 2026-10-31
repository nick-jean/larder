import { formatRange, type Recipe } from "@larder/parser";

export function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

function safeHref(url: string | null): string | null {
  return url && /^https?:\/\//i.test(url) ? url : null;
}

function minutes(m: number | null, label: string): string | null {
  if (m === null) return null;
  return `${label} ${m >= 60 ? `${Math.floor(m / 60)} hr${m % 60 ? ` ${m % 60} min` : ""}` : `${m} min`}`;
}

export function recipeToHtml(r: Recipe): string {
  const meta = [r.yieldText ?? (r.servings ? `Serves ${r.servings}` : null), minutes(r.prepMinutes, "Prep"), minutes(r.cookMinutes, "Cook"), minutes(r.totalMinutes, "Total")]
    .filter(Boolean)
    .join(" · ");
  const href = safeHref(r.source.url);
  const by = r.source.creatorHandle ?? r.source.creatorName;
  const ingredients = r.ingredients
    .map((i) => {
      if (i.isSection) return `<li class="section">${escapeHtml(i.item)}</li>`;
      const qty = [formatRange(i.quantity, i.quantityMax), i.unitRaw ?? i.unit ?? ""].filter(Boolean).join(" ");
      return `<li>${qty ? `<b>${escapeHtml(qty)}</b> ` : ""}${escapeHtml(i.item)}${i.note ? `, ${escapeHtml(i.note)}` : ""}</li>`;
    })
    .join("");
  return [
    `<article id="${escapeHtml(r.id)}">`,
    `<h2>${escapeHtml(r.title || "Untitled recipe")}</h2>`,
    meta ? `<p class="meta">${escapeHtml(meta)}</p>` : "",
    by || href ? `<p class="source">${by ? `By ${escapeHtml(by)} ` : ""}${href ? `<a href="${escapeHtml(href)}">original</a>` : ""}</p>` : "",
    ingredients ? `<h3>Ingredients</h3><ul>${ingredients}</ul>` : "",
    r.steps.length ? `<h3>Steps</h3><ol>${r.steps.map((s) => `<li>${escapeHtml(s.text)}</li>`).join("")}</ol>` : "",
    r.notes ? `<h3>Notes</h3><p>${escapeHtml(r.notes).replace(/\n/g, "<br>")}</p>` : "",
    r.tags.length ? `<p class="tags">${r.tags.map((t) => `#${escapeHtml(t)}`).join(" ")}</p>` : "",
    `</article>`,
  ].join("");
}

export function libraryToHtml(recipes: Recipe[], exportedAt: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Larder library</title>
<style>body{font-family:system-ui,sans-serif;max-width:720px;margin:2rem auto;padding:0 1rem;color:#222}article{border-top:1px solid #ddd;padding:1rem 0}.meta,.source,.tags{color:#666;font-size:.9rem}li.section{list-style:none;font-weight:600;margin-top:.5rem}</style>
</head><body><h1>Larder library</h1><p class="meta">${recipes.length} recipes · exported ${escapeHtml(exportedAt)}</p>${recipes.map(recipeToHtml).join("\n")}</body></html>`;
}
