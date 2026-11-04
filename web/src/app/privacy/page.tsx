import type { Metadata } from "next";

export const metadata: Metadata = { title: "Privacy" };

export default function Privacy() {
  return (
    <article className="mx-auto max-w-3xl px-6 py-16 text-[15px] leading-7">
      <h1 className="text-3xl font-bold tracking-tight">Privacy policy</h1>
      <p className="mt-2 text-sm text-muted">Draft, last updated October 2026</p>

      <h2 className="mt-10 text-xl font-semibold">What we collect</h2>
      <ul className="mt-3 list-disc space-y-2 pl-6">
        <li><strong>Recipes</strong> you import, write or edit, with their source link and creator credit.</li>
        <li><strong>Account details</strong> from Apple, Google or email sign-in: an identifier, display name and email. Without an account, your library stays on your device only.</li>
        <li><strong>Links you import.</strong> We fetch public information for that one link (for example TikTok&apos;s public caption or a recipe page) and cache it briefly so repeat imports are fast.</li>
        <li><strong>Photos.</strong> Cookbook pages, cards and screenshots are read on your device and stay there.</li>
      </ul>

      <h2 className="mt-10 text-xl font-semibold">Clipboard</h2>
      <p className="mt-3">
        Larder checks whether your clipboard probably holds a link without reading it, and reads it only when you tap
        Import or Paste. You can turn the clipboard banner off in settings.
      </p>

      <h2 className="mt-10 text-xl font-semibold">Optional cloud help</h2>
      <p className="mt-3">
        If on-device reading struggles (for example messy handwriting), you can choose to send that photo or text to our
        server for a second read by a third-party OCR or AI provider on a paid tier that doesn&apos;t train on your data.
        Nothing is sent without your tap, and images are not stored after processing.
      </p>

      <h2 className="mt-10 text-xl font-semibold">Social accounts</h2>
      <p className="mt-3">
        Larder never asks for your TikTok, Instagram or Facebook login, never reads your saved or liked posts, and never
        downloads videos.
      </p>

      <h2 className="mt-10 text-xl font-semibold">Your choices</h2>
      <ul className="mt-3 list-disc space-y-2 pl-6">
        <li>Export your whole library at any time (JSON or HTML).</li>
        <li>Delete your account from the app. This deletes your recipes from our servers.</li>
      </ul>
    </article>
  );
}
