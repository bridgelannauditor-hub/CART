import 'dart:async';

import 'package:flutter/material.dart';
import 'screens/customer/messages_screen.dart';

import 'config/supabase_config.dart';
import 'constants/app_colors.dart';
import 'database/seed_data.dart';
import 'services/session_service.dart';

import 'utils/routes.dart';

import 'screens/splash/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/account_type_screen.dart';
import 'screens/auth/forgot_password_screen.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseConfig.initialize();

  runApp(const CArtApp());

  // Local category setup is not required to render the first screen. Starting
  // it after the first frame keeps SQLite creation and migrations off the
  // critical startup path.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_seedLocalData());
  });
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

class CArtApp extends StatelessWidget {
  const CArtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'C+ART',

      theme: ThemeData(
        useMaterial3: true,

        scaffoldBackgroundColor: AppColors.background,

        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.dark,
          elevation: 0,
        ),

        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: AppColors.textPrimary),
          bodyMedium: TextStyle(color: AppColors.textPrimary),
        ),
      ),

      initialRoute: AppRoutes.splash,
      onGenerateRoute: _onGenerateRoute,
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
      AppRoutes.register => const AccountTypeScreen(),
      AppRoutes.registerDetails => RegisterScreen(
        initialAccountType: 'Customer',
      ),
      AppRoutes.forgotPassword => const ForgotPasswordScreen(),
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
