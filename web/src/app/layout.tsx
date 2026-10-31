import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import Link from "next/link";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: { default: "Larder: every recipe you save, in one place", template: "%s · Larder" },
  description:
    "Paste a TikTok, Instagram, Facebook or recipe-site link, or snap a cookbook page or handwritten card. Larder turns it into a clean, searchable recipe that works offline.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col font-sans">
        <header className="border-b border-line bg-card">
          <nav className="mx-auto flex max-w-5xl items-center justify-between px-6 py-4">
            <Link href="/" className="text-lg font-bold tracking-tight text-brand-dark">
              Larder
            </Link>
            <div className="flex gap-6 text-sm text-muted">
              <Link href="/#features" className="hover:text-foreground">Features</Link>
              <Link href="/#how" className="hover:text-foreground">How it works</Link>
              <Link href="/privacy" className="hover:text-foreground">Privacy</Link>
            </div>
          </nav>
        </header>
        <main className="flex-1">{children}</main>
        <footer className="border-t border-line py-8 text-center text-xs text-muted">
          Larder (working name) · Recipes stay credited to their creators, with a link back to the original.
        </footer>
      </body>
    </html>
  );
}
