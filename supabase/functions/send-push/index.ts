// Delivers a phone push notification through Firebase Cloud Messaging (HTTP v1).
//
// The database (private.send_push) calls this function with the shared secret
// in the x-push-secret header, so it cannot be used by anyone else. It looks up
// the phones registered for the person, sends one notification to each, and
// removes any phone address Firebase reports as no longer valid.
//
// Requires the FCM_SERVICE_ACCOUNT secret (the Firebase service account key,
// as JSON). The key is only ever read here and never reaches the app.

import { createClient } from "npm:@supabase/supabase-js@2.58.0";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

let cachedToken: { value: string; expiresAt: number } | null = null;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function base64Url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (char) => char.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

// Exchanges the service account for a short-lived Google access token.
async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.value;

  const tokenUri = account.token_uri ?? "https://oauth2.googleapis.com/token";
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(
    JSON.stringify({
      iss: account.client_email,
      scope: FCM_SCOPE,
      aud: tokenUri,
      iat: now,
      exp: now + 3600,
    }),
  );
  const signingInput = `${header}.${claims}`;
  const key = await importPrivateKey(account.private_key);
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(signingInput),
    ),
  );
  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${signingInput}.${base64Url(signature)}`,
    }),
  });
  const payload = await response.json();
  if (!response.ok || !payload.access_token) {
    throw new Error(`Google token request failed (${response.status}).`);
  }
  cachedToken = {
    value: payload.access_token,
    expiresAt: now + Number(payload.expires_in ?? 3600),
  };
  return cachedToken.value;
}

function stringifyData(data: unknown): Record<string, string> {
  const result: Record<string, string> = {};
  if (data && typeof data === "object") {
    for (const [key, value] of Object.entries(data as Record<string, unknown>)) {
      result[key] = value == null ? "" : String(value);
    }
  }
  return result;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "Method not allowed." });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json(500, { error: "Server is not configured." });
  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  // Only the database knows the shared secret.
  const provided = request.headers.get("x-push-secret") ?? "";
  const { data: allowed } = await supabase.rpc("verify_push_secret", {
    candidate: provided,
  });
  if (allowed !== true) return json(401, { error: "Not allowed." });

  const rawAccount = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!rawAccount) return json(503, { error: "FCM_SERVICE_ACCOUNT is not set." });
  let account: ServiceAccount;
  try {
    account = JSON.parse(rawAccount);
  } catch {
    return json(503, { error: "FCM_SERVICE_ACCOUNT is not valid JSON." });
  }

  let payload: {
    profile_id?: number;
    title?: string;
    body?: string;
    data?: unknown;
  };
  try {
    payload = await request.json();
  } catch {
    return json(400, { error: "Invalid request." });
  }
  const profileId = Number(payload.profile_id);
  if (!Number.isFinite(profileId) || !payload.title || !payload.body) {
    return json(400, { error: "profile_id, title and body are required." });
  }

  const { data: tokens, error: tokenError } = await supabase
    .from("push_tokens")
    .select("token")
    .eq("profile_id", profileId);
  if (tokenError) return json(500, { error: "Could not read push tokens." });
  if (!tokens?.length) return json(200, { sent: 0, removed: 0 });

  let bearer: string;
  try {
    bearer = await accessToken(account);
  } catch (error) {
    return json(502, { error: (error as Error).message });
  }

  const data = stringifyData(payload.data);
  let sent = 0;
  const dead: string[] = [];

  await Promise.all(
    tokens.map(async ({ token }: { token: string }) => {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${bearer}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: payload.title, body: payload.body },
              data,
              android: {
                priority: "HIGH",
                notification: {
                  channel_id: "cart_default",
                  sound: "default",
                },
              },
            },
          }),
        },
      );
      if (response.ok) {
        sent++;
        return;
      }
      const failure = await response.json().catch(() => ({}));
      const status = failure?.error?.status as string | undefined;
      // The phone uninstalled the app or the address is no longer valid.
      if (status === "NOT_FOUND" || status === "INVALID_ARGUMENT" || response.status === 404) {
        dead.push(token);
      }
    }),
  );

  if (dead.length) await supabase.from("push_tokens").delete().in("token", dead);
  return json(200, { sent, removed: dead.length });
});
