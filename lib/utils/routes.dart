class AppRoutes {
  static const String splash = "/";
  static const String login = "/login";
  static const String register = "/register";
  static const String registerDetails = "/register/details";
  static const String forgotPassword = "/forgot-password";

  static const String home = "/home";
  static const String categories = "/categories";
  static const String watch = "/watch";
  static const String cart = "/cart";
  static const String checkout = "/checkout";
  static const String messages = "/messages";
  static const String orders = "/orders";
  static const String profile = "/profile";

  static const String sellerDashboard = "/seller-dashboard";
  static const String addProduct = "/add-product";
  static const String sellerOrders = "/seller-orders";
  static const String sellerMessages = "/seller-messages";
  static const String sellerLive = "/seller-live";
  static const String sellerProfile = "/seller-profile";

  static const Set<String> publicRoutes = {
    splash,
    login,
    register,
    registerDetails,
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
  };

  static const Set<String> sellerRoutes = {
    sellerDashboard,
    addProduct,
    sellerOrders,
    sellerMessages,
    sellerLive,
    sellerProfile,
  };

  static String resolveForSession(
    String? requested, {
    required bool loggedIn,
    String? accountType,
  }) {
    final route = requested ?? splash;
    if (route == splash) return splash;

    final isSeller = loggedIn && accountType == 'Seller';
    final isCustomer = loggedIn && accountType == 'Customer';
    if (!publicRoutes.contains(route) && !loggedIn) return login;
    if (customerRoutes.contains(route) && !isCustomer) {
      return isSeller ? sellerDashboard : login;
    }
    if (sellerRoutes.contains(route) && !isSeller) {
      return isCustomer ? home : login;
    }
    if (loggedIn && publicRoutes.contains(route)) {
      return isSeller ? sellerDashboard : home;
    }
    return route;
  }
}
