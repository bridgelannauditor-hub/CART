import 'dart:async';

import 'auth_service.dart';
import '../models/user_model.dart';
import 'push_service.dart';

class SessionService {
  static int? userId;
  static String? firebaseUid;

  static String? firstName;
  static String? lastName;
  static String? email;
  static String? accountType;
  static bool onboardingCompleted = true;

  static bool get isLoggedIn => userId != null;
  static bool get isSeller => isLoggedIn && accountType == 'Seller';
  static bool get isCustomer => isLoggedIn && accountType == 'Customer';

  static void login({
    required int id,
    String? firebaseUid,
    required String firstName,
    required String lastName,
    required String email,
    required String accountType,
    bool onboardingCompleted = true,
  }) {
    SessionService.userId = id;
    SessionService.firebaseUid = firebaseUid;
    SessionService.firstName = firstName;
    SessionService.lastName = lastName;
    SessionService.email = email;
    SessionService.accountType = accountType;
    SessionService.onboardingCompleted = onboardingCompleted;
    // Every sign-in path ends here; tell this phone to receive the user's
    // notifications (it asks for permission the first time).
    unawaited(PushService.instance.registerForCurrentUser());
  }

  static void loginUser(UserModel user) {
    final id = user.id;
    if (id == null) return;
    login(
      id: id,
      firebaseUid: user.firebaseUid,
      firstName: user.firstName,
      lastName: user.lastName,
      email: user.email,
      accountType: user.accountType,
      onboardingCompleted: user.onboardingCompleted,
    );
  }

  /// Updates whichever cached session fields are provided — used
  /// after a successful Personal Information edit so the rest of
  /// the app (header, profile card) reflects the change immediately
  /// without needing to re-login.
  static void updateProfile({
    String? firstName,
    String? lastName,
    String? email,
  }) {
    if (firstName != null) SessionService.firstName = firstName;
    if (lastName != null) SessionService.lastName = lastName;
    if (email != null) SessionService.email = email;
  }

  static Future<void> logout() async {
    // While the session is still valid, stop this phone receiving the
    // signed-out user's notifications.
    await PushService.instance.unregister();
    await AuthService().logout();
    userId = null;
    firebaseUid = null;
    firstName = null;
    lastName = null;
    email = null;
    accountType = null;
    onboardingCompleted = true;
  }
}
