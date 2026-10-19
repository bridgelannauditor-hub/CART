// Identity-verification provider adapter.
//
// Cart never receives ID or selfie images. The applicant captures the front
// and back of the ID and completes the liveness/face-match check inside the
// provider's own hosted flow. Cart receives only a session reference and, via
// a signed webhook, the outcome.
//
// To connect a real vendor, implement `VerificationProvider` for its API and
// webhook signature format, and select it with VERIFICATION_PROVIDER.

export type VerificationOutcome =
  | "verified"
  | "needs_retry"
  | "under_review"
  | "rejected";

export interface ProviderSession {
  providerSessionId: string;
  /** URL the applicant opens to capture the ID and complete liveness. */
  verificationUrl: string;
  expiresAt: string;
}

export interface ProviderResult {
  eventId: string;
  providerSessionId: string;
  outcome: VerificationOutcome;
  /** Short machine code such as "image_blurry"; never raw document data. */
  reasonCode: string | null;
  checks: {
    document?: boolean;
    liveness?: boolean;
    face_match?: boolean;
    personal_details?: boolean;
  };
}

export interface VerificationProvider {
  readonly name: string;
  createSession(input: {
    reference: string;
    documentType: string;
  }): Promise<ProviderSession>;
  /** Returns null when the signature or timestamp is invalid. */
  parseWebhook(rawBody: string, headers: Headers): Promise<ProviderResult | null>;
}

const OUTCOMES: ReadonlySet<string> = new Set([
  "verified",
  "needs_retry",
  "under_review",
  "rejected",
]);

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Generic HTTPS provider. Expects:
 *   POST {VERIFICATION_API_URL}/sessions  -> { id, url, expires_at }
 *   webhook headers x-signature-timestamp and x-signature
 *     where x-signature = hex(HMAC_SHA256(secret, `${timestamp}.${rawBody}`))
 *   webhook body { event_id, session_id, outcome, reason_code, checks }
 * Adjust the mapping to match the chosen vendor's documented API.
 */
class HttpVerificationProvider implements VerificationProvider {
  readonly name = "http";

  async createSession(input: { reference: string; documentType: string }) {
    const response = await fetch(`${requireEnv("VERIFICATION_API_URL")}/sessions`, {
      method: "POST",
      headers: {
        "authorization": `Bearer ${requireEnv("VERIFICATION_API_KEY")}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        reference: input.reference,
        document_type: input.documentType,
        checks: ["document_front", "document_back", "liveness", "face_match"],
        capture: "camera_only",
        callback_url: requireEnv("VERIFICATION_WEBHOOK_URL"),
      }),
    });
    if (!response.ok) {
      throw new Error(`Provider session request failed with ${response.status}.`);
    }
    const body = await response.json();
    if (typeof body?.id !== "string" || typeof body?.url !== "string") {
      throw new Error("Provider returned an invalid session.");
    }
    return {
      providerSessionId: body.id,
      verificationUrl: body.url,
      expiresAt: typeof body.expires_at === "string"
        ? body.expires_at
        : new Date(Date.now() + 30 * 60 * 1000).toISOString(),
    };
  }

  async parseWebhook(rawBody: string, headers: Headers) {
    const timestamp = headers.get("x-signature-timestamp") ?? "";
    const signature = (headers.get("x-signature") ?? "").toLowerCase();
    const ageSeconds = Math.abs(Date.now() / 1000 - Number(timestamp));
    if (!timestamp || !Number.isFinite(ageSeconds) || ageSeconds > 300) return null;

    const expected = await hmacSha256Hex(
      requireEnv("VERIFICATION_WEBHOOK_SECRET"),
      `${timestamp}.${rawBody}`,
    );
    if (!timingSafeEqual(expected, signature)) return null;

    const body = JSON.parse(rawBody);
    if (
      typeof body?.event_id !== "string" ||
      typeof body?.session_id !== "string" ||
      !OUTCOMES.has(body?.outcome)
    ) {
      return null;
    }
    return {
      eventId: body.event_id,
      providerSessionId: body.session_id,
      outcome: body.outcome as VerificationOutcome,
      reasonCode: typeof body.reason_code === "string"
        ? body.reason_code.slice(0, 100)
        : null,
      checks: typeof body.checks === "object" && body.checks !== null
        ? body.checks
        : {},
    };
  }
}

/**
 * Local development only. Refuses to load unless ALLOW_MOCK_VERIFICATION=true,
 * which must never be set on a production project.
 */
class MockVerificationProvider extends HttpVerificationProvider {
  override readonly name = "mock";

  override createSession(input: { reference: string; documentType: string }) {
    return Promise.resolve({
      providerSessionId: `mock_${input.reference}`,
      verificationUrl: `https://example.invalid/mock-verification/${input.reference}`,
      expiresAt: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
    });
  }
}

export function loadVerificationProvider(): VerificationProvider {
  const name = Deno.env.get("VERIFICATION_PROVIDER") ?? "";
  if (name === "http") return new HttpVerificationProvider();
  if (name === "mock") {
    if (Deno.env.get("ALLOW_MOCK_VERIFICATION") !== "true") {
      throw new Error("The mock verification provider is disabled.");
    }
    return new MockVerificationProvider();
  }
  throw new Error("VERIFICATION_PROVIDER is not configured.");
}
