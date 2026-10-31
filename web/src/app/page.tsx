const features = [
  { title: "Copy a link, get a recipe", body: "Copy the link to a TikTok, Instagram or Facebook post, or any recipe site. Open Larder and tap Import. We read the public caption and any linked recipe page, and show you exactly what we found." },
  { title: "Snap cookbooks and family cards", body: "Photograph a cookbook page, a screenshot or Grandma's handwritten card, across several pages if needed. Text is read on your phone first; the original photo stays with the recipe." },
  { title: "Confidence you can see", body: "Anything we're unsure about is highlighted next to the source, with one-tap fixes. We never quietly guess a quantity." },
  { title: "Credit where it's due", body: "Every saved recipe keeps the creator and a link back to the original post or page." },
  { title: "Works offline", body: "Your whole library lives on your phone and is searchable by title, ingredient, tag or source, with or without signal." },
  { title: "Yours to take with you", body: "Scale servings, switch between cups and grams, add notes, and export the whole library any time." },
];

const draft = [
  { qty: "2", unit: "cups", item: "all-purpose flour", ok: true },
  { qty: "1", unit: "tsp", item: "baking soda", ok: true },
  { qty: "?", unit: "cup", item: "buttermilk", ok: false },
  { qty: "4", unit: "tbsp", item: "cold butter, cubed", ok: true },
];

export default function Home() {
  return (
    <>
      <section className="mx-auto grid max-w-5xl items-center gap-12 px-6 py-20 md:grid-cols-2">
        <div>
          <p className="mb-3 text-sm font-semibold uppercase tracking-wider text-brand">Recipe keeper</p>
          <h1 className="text-4xl font-bold leading-tight tracking-tight md:text-5xl">Every recipe you save, finally in one place.</h1>
          <p className="mt-5 text-lg text-muted">
            Paste a link from TikTok, Instagram, Facebook or a recipe site, or snap a cookbook page or handwritten card.
            Larder turns it into a clean recipe you can search, scale and cook from, even offline.
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <span className="rounded-full bg-brand px-5 py-3 text-sm font-semibold text-white">Coming soon to iOS & Android</span>
          </div>
        </div>
        <div className="rounded-2xl border border-line bg-card p-5 shadow-sm">
          <div className="mb-1 flex items-center justify-between text-sm">
            <span className="font-semibold">Grandma&apos;s Buttermilk Biscuits</span>
            <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">1 to check</span>
          </div>
          <p className="mb-4 text-xs text-muted">Handwritten card · 2 pages · read on device</p>
          <ul className="space-y-2 text-sm">
            {draft.map((d) => (
              <li key={d.item} className={`flex gap-3 rounded-lg px-3 py-2 ${d.ok ? "bg-background" : "border border-amber-300 bg-amber-50"}`}>
                <span className="w-16 font-mono font-semibold">{d.qty} {d.unit}</span>
                <span>{d.item}</span>
                {!d.ok && <span className="ml-auto text-xs text-amber-800">¾ or ⅓?</span>}
              </li>
            ))}
          </ul>
        </div>
      </section>

      <section id="features" className="border-y border-line bg-card">
        <div className="mx-auto grid max-w-5xl gap-8 px-6 py-16 md:grid-cols-3">
          {features.map((f) => (
            <div key={f.title}>
              <h2 className="font-semibold">{f.title}</h2>
              <p className="mt-2 text-sm leading-6 text-muted">{f.body}</p>
            </div>
          ))}
        </div>
      </section>

      <section id="how" className="mx-auto max-w-3xl px-6 py-16">
        <h2 className="text-2xl font-bold tracking-tight">Honest about what we can read</h2>
        <p className="mt-4 leading-7 text-muted">
          Larder only uses public, official sources for the one link you give it: TikTok&apos;s public caption, a linked
          recipe page&apos;s recipe data, and anything you paste or photograph yourself. Instagram and Facebook don&apos;t share
          captions with apps, so when we can&apos;t read a post we say so and ask you to paste the caption or add a screenshot.
          We never log in to your social accounts, sync your saved posts, or download videos.
        </p>
      </section>
    </>
  );
}
