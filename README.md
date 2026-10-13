# Craft of Love

Craft of Love is a Flutter marketplace for handmade products. Customers can
follow shops, claim seller vouchers, shop across multiple sellers, select a
delivery address and payment method, and place orders. Sellers can manage
products, follower campaigns, fulfillment, analytics, chat, and LIVE shopping.

## Technology

- Flutter and Dart
- Firebase Authentication, Cloud Firestore, and Cloud Functions
- SQLite for the local cache and offline state
- Cloudinary for product and profile media
- Agora for development LIVE streaming

## Local setup

1. Install the Flutter version compatible with `pubspec.lock`.
2. Run `flutter pub get`.
3. Confirm `android/app/google-services.json` belongs to the intended Firebase
   environment.
4. Configure the required local or Firebase emulator environment.
5. Run the app with `flutter run`.

Google and Facebook login require their provider consoles, OAuth credentials,
package identifiers, signing fingerprints, and Firebase Authentication settings
to agree. Cloudinary's unsigned upload preset must enforce the same format and
size limits as the client. Agora's checked-in test channel and token are for
development only.

## Verification

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Cloud Functions and Firestore authorization have separate integration suites in
`functions/test` and `test/firestore_rules`.

## Deployment order

Deploy trusted Cloud Functions before the stricter Firestore rules and indexes.
The Firebase project must use a plan that supports Cloud Functions deployment.
Follow the smoke-test checklist and outstanding findings in
`docs/APP_AUDIT_2026-10-07.md` before a production release.
