import {
  authenticate,
  corsHeaders,
  hashSchoolEmailCode,
  json,
} from "../_shared/school_email.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (request.method !== "POST") return json(405, { error: "Method not allowed." });

  try {
    const auth = await authenticate(request);
    if (!auth) return json(401, { error: "Sign in to continue." });
    const body = await request.json().catch(() => ({}));
    const challengeId = typeof body.challengeId === "string" ? body.challengeId : "";
    const code = typeof body.code === "string" ? body.code.trim() : "";
    if (!/^[0-9a-f-]{36}$/.test(challengeId) || !/^\d{6}$/.test(code)) {
      return json(400, { error: "Enter the six-digit verification code." });
    }

    const digest = await hashSchoolEmailCode(challengeId, code);
    const { data, error } = await auth.serviceClient.rpc(
      "service_verify_school_email_challenge",
      {
        challenge_id: challengeId,
        target_auth_user_id: auth.user.id,
        submitted_hash: digest,
      },
    );
    if (error) {
      console.error("school email verification RPC failed", error);
      return json(409, { error: "The code could not be verified." });
    }
    if (!data?.verified) {
      const messages: Record<string, string> = {
        expired: "This code has expired. Request a new one.",
        attempts_exhausted: "Too many incorrect attempts. Request a new code.",
        application_changed: "Your application changed. Request a new code.",
        incorrect: "That code is incorrect.",
        invalid: "This verification request is no longer valid.",
      };
      return json(400, {
        error: messages[data?.reason] ?? "The code could not be verified.",
        attemptsRemaining: data?.attemptsRemaining,
      });
    }
    return json(200, { verified: true });
  } catch (error) {
    console.error("school email verification failed", error);
    return json(503, { error: "School-email verification is temporarily unavailable." });
  }
});
