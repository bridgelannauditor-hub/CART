class DBTables {
  DBTables._();

  // ==========================
  // Database Information
  // ==========================
  static const String databaseName = "craft_of_love.db";
  static const int databaseVersion = 17;

  // ==========================
  // CART
  // ==========================

  static const String cartItems = "cart_items";
  static const String cartId = "id";
  static const String cartUserId = "user_id";
  static const String cartProductId = "product_id";
  static const String cartQuantity = "quantity";
  static const String cartOptionId = "option_id";
  static const String cartOptionName = "option_name";
  static const String cartOptionImage = "option_image";
  static const String cartUnitPrice = "unit_price";

  // ==========================
  // Table Names
  // ==========================
  static const String users = "users";
  static const String categories = "categories";
  static const String products = "products";
  static const String orders = "orders";
  static const String orderItems = "order_items";
  static const String reviews = "reviews";
  static const String favorites = "favorites";
  static const String messages = "messages";
  static const String notifications = "notifications";
  static const String productMedia = "product_media";
  static const String productTags = "product_tags";
  static const String shopFollows = "shop_follows";
  static const String shopVisits = "shop_visits";
  static const String deliveryAddresses = "delivery_addresses";
  static const String userSettings = "user_settings";

  // ==========================
  // Common Columns
  // ==========================
  static const String id = "id";
  static const String createdAt = "created_at";

  // ==========================
  // User Columns
  // ==========================
  static const String firstName = "first_name";
  static const String lastName = "last_name";
  static const String email = "email";
  static const String phone = "phone";
  static const String accountType = "account_type";

  // ==========================
  // Category Columns
  // ==========================
  static const String categoryName = "name";
  static const String categoryImage = "image";
  static const String categoryGroup = "category_group";

  // ==========================
  // Product Columns
  // ==========================
  static const String sellerId = "seller_id";
  static const String categoryId = "category_id";
  static const String productName = "name";
  static const String description = "description";
  static const String price = "price";
  static const String stock = "stock";
  static const String image = "image";
  static const String rating = "rating";
  static const String craftType = "craft_type";
  static const String material = "material";
  static const String occasion = "occasion";
  static const String tagValue = "tag";
  static const String isFlashSale = "is_flash_sale";
  static const String discountPercent = "discount_percent";
  static const String freeShipping = "free_shipping";
  static const String codAvailable = "cod_available";

  // ==========================
  // Order Columns
  // ==========================
  static const String customerId = "customer_id";
  static const String total = "total";
  static const String status = "status";
  static const String orderDate = "order_date";

  // ==========================
  // Order Item Columns
  // ==========================
  static const String orderId = "order_id";
  static const String productId = "product_id";
  static const String quantity = "quantity";

  // ==========================
  // Review Columns
  // ==========================
  static const String reviewComment = "comment";

  // ==========================
  // Favorite Columns
  // ==========================
  static const String favoriteUserId = "user_id";
  static const String favoriteProductId = "product_id";

  // ==========================
  // Message Columns
  // ==========================
  static const String senderId = "sender_id";
  static const String receiverId = "receiver_id";
  static const String messageText = "message_text";
  static const String messageDate = "message_date";
  static const String isRead = "is_read";

  // ==========================
  // Notification Columns
  // ==========================
  static const String notifUserId = "user_id";
  static const String notifTitle = "title";
  static const String notifBody = "body";
  static const String notifType = "type";
  static const String notifRelatedId = "related_id";
  static const String notifDate = "created_date";

  // ==========================
  // Product Media Columns
  // ==========================
  static const String mediaProductId = "product_id";
  static const String mediaType = "media_type"; // "image" or "video"
  static const String mediaPath = "path";
  static const String mediaPosition = "position";

  static const String shopName = 'shop_name';

  // ==========================
  // Shop Appearance Columns
  // ==========================
  static const String coverImage = 'cover_image';
  static const String profileImage = 'profile_image';
  static const String isLive = 'is_live';

  // ==========================
  // Shop Follow Columns
  // ==========================
  static const String followFollowerId = "follower_id";
  static const String followShopId = "shop_id";

  // ==========================
  // Shop Visit Columns
  // ==========================
  static const String visitVisitorId = "visitor_id";
  static const String visitShopId = "shop_id";

  // ==========================
  // Delivery Address Columns
  // ==========================
  static const String addressUserId = "user_id";
  static const String addressFullName = "full_name";
  static const String addressPhone = "phone";
  static const String addressLabel = "label";
  static const String addressLine1 = "line1";
  static const String addressLine2 = "line2";
  static const String addressCity = "city";
  static const String addressProvince = "province";
  static const String addressPostalCode = "postal_code";
  static const String addressIsDefault = "is_default";

  // ==========================
  // User Settings Columns
  // ==========================
  static const String settingsUserId = "user_id";
  static const String settingsPushEnabled = "push_enabled";
  static const String settingsEmailEnabled = "email_enabled";
  static const String settingsOrderUpdates = "order_updates_enabled";
  static const String settingsPromoOffers = "promo_offers_enabled";
}
