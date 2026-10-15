// Starts an identity-verification session for the signed-in applicant.
//
// 1. Reserves a session through public.begin_identity_verification, called
//    with the applicant's own JWT so every eligibility rule runs in Postgres.
// 2. Creates the provider session server-to-server (the provider key never
//    reaches Flutter).
// 3. Attaches the provider reference with the service role.

import { createClient } from "npm:@supabase/supabase-js@2.58.0";

import { loadVerificationProvider } from "../_shared/verification_provider.ts";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (request.method !== "POST") return json(405, { error: "Method not allowed." });

  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json(401, { error: "Sign in to continue." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const serviceClient = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  let provider;
  try {
    provider = loadVerificationProvider();
  } catch (error) {
    console.error("verification provider unavailable", error);
    return json(503, { error: "Identity verification is temporarily unavailable." });
  }

  const { data: sessionId, error: beginError } = await userClient.rpc(
    "begin_identity_verification",
    { provider_name: provider.name },
  );
  if (beginError) {
    // Eligibility messages are written for applicants and contain no secrets.
    const status = beginError.code === "42501" ? 403 : 409;
    return json(status, { error: beginError.message, code: beginError.code });
  }

  const { data: application } = await userClient
    .from("seller_verification_applications")
    .select("identity_document_type")
    .single();

  try {
    const session = await provider.createSession({
      reference: sessionId as string,
      documentType: application?.identity_document_type ?? "national_id",
    });
    const { error: attachError } = await serviceClient.rpc(
      "service_attach_verification_session",
      {
        session_id: sessionId,
        provider_session_ref: session.providerSessionId,
        session_expires_at: session.expiresAt,
      },
    );
    if (attachError) throw attachError;

    return json(200, {
      sessionId,
      verificationUrl: session.verificationUrl,
      expiresAt: session.expiresAt,
    });
  } catch (error) {
    console.error("verification session creation failed", error);
    // A provider outage must not consume one of the applicant's attempts.
    await serviceClient.rpc("service_fail_verification_session", {
      session_id: sessionId,
      reason: "provider_unavailable",
    });
    return json(502, {
      error: "The verification service could not start. No attempt was used; please try again.",
    });
  }
});
