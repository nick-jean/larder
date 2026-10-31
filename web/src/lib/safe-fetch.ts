import { lookup, type LookupAddress } from "node:dns";
import { isIP } from "node:net";
import { Agent, fetch as undiciFetch } from "undici";

export interface FetchedPage {
  status: number;
  finalUrl: string;
  contentType: string;
  body: string;
}

export type Fetcher = (url: string, opts?: { accept?: string }) => Promise<FetchedPage>;

export class BlockedUrlError extends Error {}

/** Loopback, private, link-local, CGNAT, multicast and reserved ranges (IPv4 and IPv6). */
export function isPrivateAddress(ip: string): boolean {
  const v = isIP(ip);
  if (v === 4) {
    const [a, b] = ip.split(".").map(Number);
    return (
      a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) ||
      (a === 198 && (b === 18 || b === 19))
    );
  }
  if (v === 6) {
    const s = ip.toLowerCase();
    const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(s);
    if (mapped) return isPrivateAddress(mapped[1]);
    return s === "::" || s === "::1" || /^f[cd]/.test(s) || /^fe[89ab]/.test(s) || s.startsWith("ff");
  }
  return true;
}

type LookupCb = (err: NodeJS.ErrnoException | null, address: string | LookupAddress[], family?: number) => void;

const agent = new Agent({
  connect: {
    timeout: 5_000,
    // Resolve and check every address before connecting, so DNS can't point us at internal hosts.
    lookup: (hostname: string, options: { all?: boolean }, cb: LookupCb) => {
      lookup(hostname, { all: true }, (err, addresses) => {
        if (err) return cb(err, "");
        const list = addresses as LookupAddress[];
        if (list.length === 0 || list.some((a) => isPrivateAddress(a.address))) {
          return cb(new BlockedUrlError(`Blocked address for ${hostname}`) as NodeJS.ErrnoException, "");
        }
        if (options?.all) return cb(null, list);
        cb(null, list[0].address, list[0].family);
      });
    },
  } as never,
});

const MAX_BYTES = 3_000_000;
const UA = "Mozilla/5.0 (compatible; LarderBot/0.1; +https://larder.app/bot)";

function checkUrl(raw: string): URL {
  const url = new URL(raw);
  if (url.protocol !== "https:" && url.protocol !== "http:") throw new BlockedUrlError("Only http(s) links are supported");
  if (url.username || url.password) throw new BlockedUrlError("Links with credentials are not supported");
  if (url.port && url.port !== "80" && url.port !== "443") throw new BlockedUrlError("Non-standard ports are not supported");
  const host = url.hostname.replace(/^\[|\]$/g, "");
  if (isIP(host) && isPrivateAddress(host)) throw new BlockedUrlError("Private addresses are not allowed");
  if (host === "localhost" || host.endsWith(".localhost") || host.endsWith(".internal") || host.endsWith(".local")) {
    throw new BlockedUrlError("Private hosts are not allowed");
  }
  return url;
}

/** GET a public URL: follows up to 5 redirects (each re-checked), 8 s timeout, 3 MB cap. */
export const safeFetch: Fetcher = async (raw, opts = {}) => {
  let url = checkUrl(raw);
  for (let hop = 0; hop <= 5; hop++) {
    const res = await undiciFetch(url, {
      dispatcher: agent,
      redirect: "manual",
      signal: AbortSignal.timeout(8_000),
      headers: { "user-agent": UA, accept: opts.accept ?? "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.5" },
    });
    const location = res.headers.get("location");
    if (res.status >= 300 && res.status < 400 && location) {
      await res.body?.cancel();
      url = checkUrl(new URL(location, url).toString());
      continue;
    }
    const contentType = res.headers.get("content-type") ?? "";
    let body = "";
    if (res.body && /text|json|xml/i.test(contentType || "text")) {
      const reader = res.body.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_BYTES) {
          await reader.cancel();
          break;
        }
        chunks.push(value);
      }
      body = Buffer.concat(chunks).toString("utf8");
    } else {
      await res.body?.cancel();
    }
    return { status: res.status, finalUrl: url.toString(), contentType, body };
  }
  throw new BlockedUrlError("Too many redirects");
};
