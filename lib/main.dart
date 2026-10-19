import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/customer/messages_screen.dart';

import 'config/supabase_config.dart';
import 'constants/app_colors.dart';
import 'database/seed_data.dart';
import 'services/session_service.dart';

import 'utils/routes.dart';

import 'screens/splash/splash_screen.dart';
import 'screens/auth/account_suspended_screen.dart';
import 'services/push_service.dart';
import 'widgets/account_warning_dialog.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/customer_register_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'services/auth_service.dart';

import 'screens/customer/home_screen.dart';
import 'screens/customer/categories_screen.dart';
import 'screens/customer/watch_screen.dart';
import 'screens/customer/cart_screen.dart';
import 'screens/customer/checkout_screen.dart';
import 'screens/customer/orders_screen.dart';
import 'screens/customer/profile_screen.dart';
import 'screens/customer/seller_onboarding_screen.dart';

import 'screens/seller/seller_dashboard_screen.dart';
import 'screens/seller/add_product_screen.dart';
import 'screens/seller/seller_orders_screen.dart';
import 'screens/seller/seller_live_screen.dart';
import 'screens/seller/seller_profile_screen.dart';
import 'repositories/admin_repository.dart';
import 'screens/admin/admin_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SupabaseConfig.initialize();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        context: ErrorDescription('while initializing Supabase'),
      ),
    );
    runApp(const _StartupFailureApp());
    return;
  }

  runApp(const CArtApp());

  // Local category setup is not required to render the first screen. Starting
  // it after the first frame keeps SQLite creation and migrations off the
  // critical startup path.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_seedLocalData());
  });
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.settings_suggest_outlined,
                    size: 48,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'App setup is incomplete',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check the Supabase development configuration and rebuild the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: 0.72),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _seedLocalData() async {
  try {
    // TODO: remove once every table has been migrated off sqflite (SeedData
    // still seeds the tables that haven't been migrated to Firestore yet).
    await SeedData.insertInitialData();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        context: ErrorDescription('while seeding the local database'),
      ),
    );
  }
}

class CArtApp extends StatefulWidget {
  const CArtApp({super.key});

  @override
  State<CArtApp> createState() => _CArtAppState();
}

class _CArtAppState extends State<CArtApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;
  bool _handlingAuthCallback = false;

  @override
  void initState() {
    super.initState();
    if (!SupabaseConfig.isConfigured) return;
    unawaited(PushService.instance.init(_navigatorKey));

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        AuthService.clearOAuthRedirectPending();
        unawaited(_handlePasswordRecovery());
      } else if (state.event == AuthChangeEvent.signedIn &&
          AuthService.takeOAuthRedirectPending()) {
        unawaited(_completeOAuthSignIn());
      }
    });

    final startupEvent = SupabaseConfig.takeStartupAuthEvent();
    if (startupEvent != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (startupEvent == AuthChangeEvent.passwordRecovery) {
          unawaited(_handlePasswordRecovery());
        } else if (startupEvent == AuthChangeEvent.signedIn) {
          unawaited(_completeOAuthSignIn());
        }
      });
    }
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  Future<void> _handlePasswordRecovery() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.pushNamedAndRemoveUntil(
      AppRoutes.resetPassword,
      (route) => false,
    );
  }

  Future<void> _completeOAuthSignIn() async {
    if (_handlingAuthCallback) return;
    _handlingAuthCallback = true;
    try {
      final profile = await AuthService().restoreSession();
      if (!mounted) return;
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;

      if (profile == null) {
        await AuthService().logout();
        unawaited(
          navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(navigator.context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
            content: Text('Could not load your profile. Please sign in again.'),
          ),
        );
        return;
      }

      // A suspended account sees why instead of the dashboard or home page.
      final suspension = await AuthService().suspensionReason();
      if (!mounted) return;
      if (suspension != null) {
        await AuthService().logout();
        unawaited(
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => AccountSuspendedScreen(reason: suspension),
            ),
            (route) => false,
          ),
        );
        return;
      }

      if (navigator.context.mounted) {
        await showPendingAccountWarnings(navigator.context);
      }
      if (!mounted) return;
      SessionService.loginUser(profile);
      final isAdmin = await AdminRepository().isAdmin();
      final destination = isAdmin
          ? AppRoutes.adminDashboard
          : profile.accountType == 'Seller'
          ? AppRoutes.sellerDashboard
          : AppRoutes.home;
      unawaited(
        navigator.pushNamedAndRemoveUntil(destination, (route) => false),
      );
    } finally {
      _handlingAuthCallback = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,

      title: 'C+ART',

      theme: _buildTheme(),

      // Respect the user's font-size setting, but cap it so layouts survive.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },

      initialRoute: AppRoutes.splash,
      onGenerateRoute: _onGenerateRoute,
    );
  }

  ThemeData _buildTheme() {
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.lightGrey),
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.dark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimary),
        bodyMedium: TextStyle(color: AppColors.textPrimary),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.error, width: 1.6),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 48),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final routeName = AppRoutes.resolveForSession(
      settings.name,
      loggedIn: SessionService.isLoggedIn,
      accountType: SessionService.accountType,
    );

    final Widget screen = switch (routeName) {
      AppRoutes.splash => const SplashScreen(),
      AppRoutes.login => const LoginScreen(),
      AppRoutes.register => const CustomerRegisterScreen(),
      AppRoutes.forgotPassword => const ForgotPasswordScreen(),
      AppRoutes.resetPassword => const ResetPasswordScreen(),
      AppRoutes.home => const HomeScreen(),
      AppRoutes.categories => const CategoriesScreen(),
      AppRoutes.watch => const WatchScreen(),
      AppRoutes.cart => const CartScreen(),
      AppRoutes.checkout => const CheckoutScreen(),
      AppRoutes.messages => const MessagesScreen(),
      AppRoutes.orders => const OrdersScreen(),
      AppRoutes.profile => const ProfileScreen(),
      AppRoutes.sellerApplication => const SellerOnboardingScreen(),
      AppRoutes.sellerDashboard => const SellerDashboardScreen(),
      AppRoutes.addProduct => const AddProductScreen(),
      AppRoutes.sellerOrders => const SellerOrdersScreen(),
      AppRoutes.sellerMessages => const MessagesScreen(isSeller: true),
      AppRoutes.sellerLive => const SellerLiveScreen(),
      AppRoutes.sellerProfile => const SellerProfileScreen(),
      AppRoutes.adminDashboard => const AdminDashboardScreen(),
      _ =>
        SessionService.isSeller
            ? const SellerDashboardScreen()
            : SessionService.isCustomer
            ? const HomeScreen()
            : const LoginScreen(),
    };

    return MaterialPageRoute<void>(
      settings: RouteSettings(name: routeName, arguments: settings.arguments),
      builder: (_) => screen,
    );
  }
}
