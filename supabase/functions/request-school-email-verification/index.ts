import {
  authenticate,
  corsHeaders,
  hashSchoolEmailCode,
  json,
  maskEmail,
  requireEnv,
} from "../_shared/school_email.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (request.method !== "POST") return json(405, { error: "Method not allowed." });

  try {
    const auth = await authenticate(request);
    if (!auth) return json(401, { error: "Sign in to continue." });

    const { data: application, error: applicationError } = await auth.userClient
      .from("seller_verification_applications")
      .select("seller_type, revision, school_email, school_email_verified, status")
      .single();
    if (applicationError || application?.seller_type !== "student" ||
      application?.status !== "under_review" || application?.school_email_verified) {
      return json(409, { error: "School-email verification is not available." });
    }

    const challengeId = crypto.randomUUID();
    const random = new Uint32Array(1);
    crypto.getRandomValues(random);
    const code = String(100000 + (random[0] % 900000));
    const digest = await hashSchoolEmailCode(challengeId, code);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const { data: storedId, error: storeError } = await auth.serviceClient.rpc(
      "service_create_school_email_challenge",
      {
        target_auth_user_id: auth.user.id,
        expected_email: application.school_email,
        expected_revision: application.revision,
        challenge_hash: digest,
        challenge_expires_at: expiresAt,
        requested_challenge_id: challengeId,
      },
    );
    if (storeError) {
      const status = storeError.code === "P0001" ? 429 : 409;
      return json(status, { error: storeError.message });
    }

    // Temporary prototype mode. The code is returned only to the signed-in
    // applicant who requested it. This verifies no mailbox ownership and must
    // be removed before launch. Seller activation still requires admin review.
    if (Deno.env.get("ALLOW_MOCK_SCHOOL_EMAIL") === "true") {
      return json(200, {
        challengeId: storedId,
        maskedEmail: maskEmail(application.school_email),
        expiresInSeconds: 600,
        prototypeCode: code,
      });
    }

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${requireEnv("RESEND_API_KEY")}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        from: requireEnv("SCHOOL_EMAIL_FROM"),
        to: [application.school_email],
        subject: "Verify your school email for C+ART",
        html: `<p>Your C+ART verification code is:</p><p style="font-size:28px;font-weight:700;letter-spacing:6px">${code}</p><p>This code expires in 10 minutes. If you did not request it, you can ignore this email.</p>`,
      }),
    });
    if (!response.ok) {
      console.error("school email delivery failed", response.status, await response.text());
      await auth.serviceClient.rpc("service_cancel_school_email_challenge", {
        challenge_id: storedId,
        target_auth_user_id: auth.user.id,
      });
      return json(502, { error: "The verification email could not be sent. Please try again." });
    }

    return json(200, {
      challengeId: storedId,
      maskedEmail: maskEmail(application.school_email),
      expiresInSeconds: 600,
    });
  } catch (error) {
    console.error("school email request failed", error);
    return json(503, { error: "School-email verification is temporarily unavailable." });
  }
});
