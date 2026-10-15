// Receives identity-verification results from the provider.
//
// The request is trusted only after the provider adapter has verified its
// signature and timestamp. The result is then recorded with the service role;
// public.service_record_verification_result is idempotent per event id.
//
// Deploy with JWT verification disabled for this function only, because the
// provider calls it without a Supabase session:
//   supabase functions deploy verification-webhook --no-verify-jwt

import { createClient } from "npm:@supabase/supabase-js@2.58.0";

import { loadVerificationProvider } from "../_shared/verification_provider.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response(null, { status: 405 });

  const rawBody = await request.text();
  if (rawBody.length > 64 * 1024) return new Response(null, { status: 413 });

  let result;
  try {
    result = await loadVerificationProvider().parseWebhook(rawBody, request.headers);
  } catch (error) {
    console.error("verification webhook rejected", error);
    return new Response(null, { status: 400 });
  }
  if (!result) return new Response(null, { status: 401 });

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { error } = await serviceClient.rpc("service_record_verification_result", {
    provider_session_ref: result.providerSessionId,
    event_id: result.eventId,
    outcome: result.outcome,
    reason: result.reasonCode,
    check_results: result.checks,
  });
  if (error) {
    console.error("verification result not recorded", error.code);
    // Unknown sessions are acknowledged so the provider stops retrying;
    // other failures ask the provider to retry later.
    return new Response(null, { status: error.code === "P0002" ? 202 : 500 });
  }
  return new Response(null, { status: 204 });
});
