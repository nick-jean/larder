import { unstable_rethrow } from "next/navigation";
import type { z } from "zod";
import { AuthError, verifyRequest, type AuthUser } from "./auth";
import { hasDatabase } from "./db";

export class HttpError extends Error {
  constructor(
    public status: number,
    message: string,
    public details?: unknown,
    public headers?: Record<string, string>,
  ) {
    super(message);
  }
}

export function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return Response.json(data, { status, headers: { "cache-control": "no-store", ...headers } });
}

export async function parseBody<T extends z.ZodType>(request: Request, schema: T): Promise<z.infer<T>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new HttpError(400, "Body must be valid JSON");
  }
  const result = schema.safeParse(body);
  if (!result.success) throw new HttpError(400, "Invalid request body", result.error.issues);
  return result.data;
}

function toResponse(err: unknown): Response {
  if (err instanceof HttpError) {
    return json({ error: err.message, ...(err.details ? { details: err.details } : {}) }, err.status, err.headers);
  }
  if (err instanceof AuthError) return json({ error: err.message }, 401);
  console.error(err);
  return json({ error: "Internal error" }, 500);
}

type Handler<C> = (request: Request, ctx: C) => Promise<Response>;

export function handle<C>(fn: Handler<C>): Handler<C> {
  return async (request, ctx) => {
    try {
      return await fn(request, ctx);
    } catch (err) {
      unstable_rethrow(err);
      return toResponse(err);
    }
  };
}

export function authed<C>(fn: (request: Request, user: AuthUser, ctx: C) => Promise<Response>): Handler<C> {
  return handle(async (request, ctx) => {
    const user = await verifyRequest(request);
    return fn(request, user, ctx);
  });
}

export function requireDatabase(): void {
  if (!hasDatabase()) throw new HttpError(503, "Database is not configured");
}
