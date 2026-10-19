# Phone push notifications

C+ART sends phone notifications through Firebase Cloud Messaging (FCM). Supabase
decides **what** to send; Firebase only **delivers** it. Orders, messages and
users stay in Supabase.

| Event | Who is notified |
| --- | --- |
| New chat message | The receiver (sender's name and the message text) |
| New order | The seller |
| Order status change | The customer |
| Admin warning | The warned account |

Anything added to `public.notifications` becomes a push, unless the user turned
push off in Settings (`notification_preferences.pushEnabled`).

## How it works

1. On sign-in the app asks for notification permission and calls
   `register_push_token` with the phone's FCM token (`lib/services/push_service.dart`).
   Signing out calls `unregister_push_token`.
2. Triggers on `public.notifications` and `public.messages` call
   `private.send_push`, which posts to the `send-push` Edge Function over `pg_net`.
   A random shared secret in Supabase Vault (`push_webhook_secret`) authenticates
   the call; a wrong secret gets `401`.
3. `supabase/functions/send-push` reads the person's tokens, signs in to Google
   with the service account, and sends one FCM message per phone. Tokens Firebase
   reports as invalid are deleted.
4. Tapping a push opens the chat, orders or notifications screen.

Files: `supabase/migrations/202610180008_push_notifications.sql`,
`supabase/functions/send-push/index.ts`, `lib/services/push_service.dart`.

## One-time setup for a Firebase project

1. In the [Firebase console](https://console.firebase.google.com) open (or create)
   the project, and make sure an **Android** app with package name
   `com.craftoflove.craft_of_love` exists. Confirm **Firebase Cloud Messaging
   API (V1)** is enabled (Project settings > Cloud Messaging).
2. Download **`google-services.json`** (Project settings > General > Your apps)
   into `android/app/`. It is git-ignored: each developer supplies their own.
   Without it the app still builds and runs; push is simply off.
3. Create a sending key: Project settings > Service accounts > **Generate new
   private key**. Treat the file as a secret. Do not commit it or paste it into
   chat.
4. In the Supabase dashboard open **Edge Functions > Secrets** and add a secret
   named **`FCM_SERVICE_ACCOUNT`** whose value is the entire contents of that
   JSON file. Then delete the downloaded file.
5. Apply the migrations (the push migration enables `pg_net` and creates the
   Vault secret) and deploy the function:
   `supabase functions deploy send-push --no-verify-jwt` (the function does its
   own authentication with the shared secret).

The Supabase project URL is written into `private.send_push`; change it if you
deploy to a different project.

## Testing

With the app installed, signed in, and notifications allowed, close the app and
add a row for that user:

```sql
insert into public.notifications (user_id, title, body, type)
values (<profile id>, 'Push test', 'It works.', 'system');
```

The phone should show the notification. `select * from net._http_response
order by id desc limit 3;` shows what the Edge Function answered
(`{"sent":1,...}` on success).

## Notes

- Android force-stop pauses pushes until the app is opened once.
- Android 13+ asks for permission on first launch.
- iOS is not configured.
- Rotating the key: generate a new one in Firebase and replace the
  `FCM_SERVICE_ACCOUNT` secret.
