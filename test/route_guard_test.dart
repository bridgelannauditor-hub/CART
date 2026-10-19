import 'package:craft_of_love/utils/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('anonymous users are redirected away from protected routes', () {
    expect(
      AppRoutes.resolveForSession(AppRoutes.orders, loggedIn: false),
      AppRoutes.login,
    );
  });

  test('the single registration route remains public for anonymous users', () {
    expect(
      AppRoutes.resolveForSession(AppRoutes.register, loggedIn: false),
      AppRoutes.register,
    );
  });

  test('password recovery callback bypasses normal session redirects', () {
    expect(
      AppRoutes.resolveForSession(
        AppRoutes.resetPassword,
        loggedIn: true,
        accountType: 'Customer',
      ),
      AppRoutes.resetPassword,
    );
    expect(
      AppRoutes.resolveForSession(AppRoutes.resetPassword, loggedIn: false),
      AppRoutes.resetPassword,
    );
  });

  test('customers cannot open seller routes', () {
    expect(
      AppRoutes.resolveForSession(
        AppRoutes.sellerDashboard,
        loggedIn: true,
        accountType: 'Customer',
      ),
      AppRoutes.home,
    );
  });

  test('sellers can open customer routes to shop as Buyers', () {
    expect(
      AppRoutes.resolveForSession(
        AppRoutes.checkout,
        loggedIn: true,
        accountType: 'Seller',
      ),
      AppRoutes.checkout,
    );
  });

  test('authenticated users are redirected away from auth screens', () {
    expect(
      AppRoutes.resolveForSession(
        AppRoutes.login,
        loggedIn: true,
        accountType: 'Seller',
      ),
      AppRoutes.sellerDashboard,
    );
  });

  test('role-matching routes remain available', () {
    expect(
      AppRoutes.resolveForSession(
        AppRoutes.orders,
        loggedIn: true,
        accountType: 'Customer',
      ),
      AppRoutes.orders,
    );
  });

  test('seller applications are an authenticated customer operation', () {
    expect(
      AppRoutes.resolveForSession(
        AppRoutes.sellerApplication,
        loggedIn: true,
        accountType: 'Customer',
      ),
      AppRoutes.sellerApplication,
    );
    expect(
      AppRoutes.resolveForSession(AppRoutes.sellerApplication, loggedIn: false),
      AppRoutes.login,
    );
  });

  test('admin dashboard requires an authenticated session', () {
    expect(
      AppRoutes.resolveForSession(AppRoutes.adminDashboard, loggedIn: false),
      AppRoutes.login,
    );
    expect(
      AppRoutes.resolveForSession(
        AppRoutes.adminDashboard,
        loggedIn: true,
        accountType: 'Customer',
      ),
      AppRoutes.adminDashboard,
    );
  });
}
