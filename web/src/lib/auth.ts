import { createRemoteJWKSet, jwtVerify } from "jose";

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);

export interface AuthUser {
  uid: string;
  name?: string;
  email?: string;
}

export class AuthError extends Error {}

/**
 * Verifies a Firebase ID token (RS256, issuer securetoken.google.com/<project>).
 * When AUTH_DEV_BYPASS=1 outside production, "Bearer dev:<uid>" is accepted for local testing.
 */
export async function verifyRequest(request: Request): Promise<AuthUser> {
  const header = request.headers.get("authorization") ?? "";
  const [scheme, token] = header.split(" ");
  if (scheme !== "Bearer" || !token) throw new AuthError("Missing bearer token");

  if (devBypassEnabled() && token.startsWith("dev:")) {
    const uid = token.slice(4);
    if (!uid) throw new AuthError("Empty dev uid");
    return { uid, name: uid };
  }

  const projectId = process.env.FIREBASE_PROJECT_ID;
  if (!projectId) throw new AuthError("Auth is not configured");
  try {
    const { payload } = await jwtVerify(token, FIREBASE_JWKS, {
      issuer: `https://securetoken.google.com/${projectId}`,
      audience: projectId,
      algorithms: ["RS256"],
    });
    if (!payload.sub) throw new AuthError("Token has no subject");
    return {
      uid: payload.sub,
      name: typeof payload.name === "string" ? payload.name : undefined,
      email: typeof payload.email === "string" ? payload.email : undefined,
    };
  } catch (err) {
    if (err instanceof AuthError) throw err;
    throw new AuthError("Invalid token");
  }
}

function devBypassEnabled(): boolean {
  return process.env.AUTH_DEV_BYPASS === "1" && process.env.NODE_ENV !== "production";
}
