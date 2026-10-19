class AppRoutes {
  static const String splash = "/";
  static const String login = "/login";
  static const String register = "/register";
  static const String forgotPassword = "/forgot-password";
  static const String resetPassword = "/reset-password";

  static const String home = "/home";
  static const String categories = "/categories";
  static const String watch = "/watch";
  static const String cart = "/cart";
  static const String checkout = "/checkout";
  static const String messages = "/messages";
  static const String orders = "/orders";
  static const String profile = "/profile";
  static const String sellerApplication = "/seller-application";

  static const String sellerDashboard = "/seller-dashboard";
  static const String addProduct = "/add-product";
  static const String sellerOrders = "/seller-orders";
  static const String sellerMessages = "/seller-messages";
  static const String sellerLive = "/seller-live";
  static const String sellerProfile = "/seller-profile";

  static const String adminDashboard = "/admin-dashboard";

  static const Set<String> publicRoutes = {
    splash,
    login,
    register,
    forgotPassword,
  };

  static const Set<String> customerRoutes = {
    home,
    categories,
    watch,
    cart,
    checkout,
    messages,
    orders,
    profile,
    sellerApplication,
  };

  static const Set<String> sellerRoutes = {
    sellerDashboard,
    addProduct,
    sellerOrders,
    sellerMessages,
    sellerLive,
    sellerProfile,
  };

  static const Set<String> authenticatedRoutes = {adminDashboard};

  static String resolveForSession(
    String? requested, {
    required bool loggedIn,
    String? accountType,
  }) {
    final route = requested ?? splash;
    if (route == splash) return splash;
    // A recovery callback creates a temporary Supabase session. Keep this
    // destination available even when another app session was already cached.
    if (route == resetPassword) return resetPassword;

    final isSeller = loggedIn && accountType == 'Seller';
    if (!publicRoutes.contains(route) && !loggedIn) return login;
    if (authenticatedRoutes.contains(route)) return route;
    // Approved Sellers retain the complete Buyer experience. These routes
    // select the shopping interface; they do not reduce backend permissions.
    if (customerRoutes.contains(route) && !loggedIn) {
      return login;
    }
    if (sellerRoutes.contains(route) && !isSeller) {
      return loggedIn ? home : login;
    }
    if (loggedIn && publicRoutes.contains(route)) {
      return isSeller ? sellerDashboard : home;
    }
    return route;
  }
}
