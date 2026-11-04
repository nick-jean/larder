# Larder

Recipe keeper: paste a TikTok, Instagram, Facebook or recipe-site link, or snap a cookbook page or handwritten card, and get a clean, searchable, cookable recipe. ("Larder" is a placeholder name.)

Spec: [Larder design doc (Notion)](https://app.notion.com/p/Larder-Recipe-Keeper-App-Design-Doc-Oct-20-2026-3ff2a7689e9081749562c7f4864a73b3).

## Layout

| Path | What |
| --- | --- |
| `packages/parser` | Shared TypeScript source of truth: recipe schema (Zod), ingredient-line parser, caption/OCR text → recipe structurer with per-field confidence, schema.org Recipe JSON-LD extractor, link classifier, scaling and US⇄metric conversion. `vectors/*.json` are shared test vectors the app's Dart port must also pass. |
| `web` | Next.js on Vercel: landing + privacy pages and the `/api/v1` API (MongoDB, Firebase auth). |
| `app` | Flutter app for iOS and Android: offline SQLite library with search and filters, paste-link import, cookbook/handwritten/screenshot scan with on-device OCR, review & edit with confidence highlights, recipe detail with scaling and US⇄metric, export, Firebase sign-in + sync. `lib/parser` is a Dart port of `packages/parser`, tested against the same vectors. |

## API (`/api/v1`)

All routes except `health` need `Authorization: Bearer <Firebase ID token>`.

| Route | |
| --- | --- |
| `GET health` | Which integrations are configured. |
| `GET/PUT me` | Profile, monthly import allowance, clipboard-banner setting. |
| `POST imports/link` | One link → receipt + draft. Public official sources only: resolve short link → TikTok oEmbed caption (Meta oEmbed if `META_OEMBED_TOKEN` is set) → linked recipe page JSON-LD → caption text. Instagram/Facebook posts that can't be read return `needsUserText` with a plain message. Results are cached per canonical URL for 7 days. Outbound fetches block private/internal addresses. |
| `POST imports/text` | Pasted caption/recipe text or on-device OCR lines → draft (rules, free). `ai: true` opts into Gemini structuring, grounded against the text so quantities are never invented; rate limited. |
| `POST imports/image` | Opt-in cloud OCR (Google Cloud Vision) for messy handwriting; rate limited, images not stored. |
| `POST sync` | Last-writer-wins recipe sync (version, then `updatedAt`), owner isolated. |
| `GET export?format=json\|html` | Full library export. |

Free tier: unlimited manual and web imports; social, AI and cloud-OCR imports count against a monthly allowance (`FREE_IMPORTS_PER_MONTH` in `web/src/lib/users.ts`). Per-account and global rate limits are env-tunable (see `web/.env.example`).

## Development

```sh
pnpm install
pnpm typecheck && pnpm lint && pnpm test
pnpm --filter web build
pnpm --filter web dev:demo   # API on :3000 with in-memory MongoDB and "Bearer dev:<uid>" auth
```

Example:

```sh
curl -s localhost:3000/api/v1/imports/text -H 'authorization: Bearer dev:me' -H 'content-type: application/json' \
  -d '{"text":"Toast\n2 slices bread\nToast the bread."}'
```

### App

```sh
cd app
flutter analyze && flutter test
# Against the local demo API (Android emulator: use http://10.0.2.2:3000):
flutter run --dart-define=LARDER_API=http://localhost:3000 --dart-define=LARDER_DEV_UID=me
```

Without `LARDER_API` the app runs fully offline (links are kept and the caption is pasted or screenshotted). Without Firebase config files (`GoogleService-Info.plist`, `google-services.json`) it runs in guest mode.
