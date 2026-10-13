# Supabase Google and Facebook sign-in

The Flutter app uses Supabase's browser-based OAuth flow. It does not use the
native `google_sign_in` or `flutter_facebook_auth` SDKs.

## Shared URLs

- Supabase provider callback (add this in both provider consoles):
  `https://dhomvejmqkznumjrrarw.supabase.co/auth/v1/callback`
- Mobile app redirect (allow this in Supabase Auth > URL Configuration):
  `io.supabase.flutter://login-callback/`

The mobile redirect is already declared in Android's `AndroidManifest.xml`,
iOS's `Info.plist`, and `lib/services/auth_service.dart`.

## Google

1. Open the Google Auth Platform for the Google Cloud project that should own
   C+ART's login.
2. Configure Branding, Audience, and Data Access. Supabase needs `openid`,
   `userinfo.email`, and `userinfo.profile`.
3. Create an OAuth client of type **Web application**.
4. Add the Supabase provider callback above to **Authorized redirect URIs**.
5. In Supabase, open **Authentication > Sign In / Providers > Google**.
6. Enable Google, enter the web client ID and client secret, then save.

While the Google OAuth app is in Testing, add each account that needs to sign
in as a test user. Publish the app when it is ready for real customers.

## Facebook

1. Create or select a Meta developer app and add the **Authentication and
   account creation** use case (Facebook Login).
2. Under Facebook Login settings, add the Supabase provider callback above to
   **Valid OAuth Redirect URIs**.
3. Ensure both `public_profile` and `email` are ready for testing.
4. Copy the Meta App ID and App Secret from **Settings > Basic**.
5. In Supabase, open **Authentication > Sign In / Providers > Facebook**.
6. Enable Facebook, enter the App ID and App Secret, then save.

In Meta Development mode, only administrators, developers, and testers can
sign in. Before real customers can use Facebook login, complete Meta's required
app details (including privacy-policy and data-deletion URLs) and switch the app
to Live mode.

## Security

- Provider client secrets belong only in the Supabase dashboard, never in the
  Flutter app or Git repository.
- The Supabase publishable/anon key may be shipped in the app; a Supabase secret
  or service-role key must never be shipped in the app.
- Test both providers on a physical Android/iOS device before release.
