import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/user_model.dart';
import '../models/cart_item_model.dart';
import 'tables.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _database;
  static Future<Database>? _databaseFuture;

  Future<Database> get database async {
    if (_database != null) return _database!;

    // Startup seeding and session restoration may both need SQLite shortly
    // after the first frame. Share one open operation instead of racing two
    // calls to openDatabase.
    final opening = _databaseFuture ??= _initDatabase();
    try {
      return _database = await opening;
    } catch (_) {
      _databaseFuture = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();

    final path = join(databasePath, DBTables.databaseName);

    return await openDatabase(
      path,
      version: DBTables.databaseVersion,
      onCreate: _onCreate,

      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // ==========================
    // USERS TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.users} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.firstName} TEXT NOT NULL,
        ${DBTables.lastName} TEXT NOT NULL,
        ${DBTables.email} TEXT UNIQUE NOT NULL,
        ${DBTables.phone} TEXT,
        ${DBTables.accountType} TEXT NOT NULL,
        ${DBTables.shopName} TEXT,
        ${DBTables.coverImage} TEXT,
        ${DBTables.profileImage} TEXT,
        ${DBTables.isLive} INTEGER NOT NULL DEFAULT 0,
        ${DBTables.createdAt} TEXT NOT NULL
      )
    ''');

    // ==========================
    // CATEGORIES TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.categories} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.categoryName} TEXT NOT NULL,
        ${DBTables.categoryImage} TEXT,
        ${DBTables.categoryGroup} TEXT
      )
    ''');

    // ==========================
    // PRODUCTS TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.products} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.sellerId} INTEGER NOT NULL,
        ${DBTables.categoryId} INTEGER NOT NULL,
        ${DBTables.productName} TEXT NOT NULL,
        ${DBTables.description} TEXT,
        ${DBTables.price} REAL NOT NULL,
        ${DBTables.stock} INTEGER NOT NULL,
        ${DBTables.image} TEXT,
        ${DBTables.rating} REAL DEFAULT 0,
        ${DBTables.craftType} TEXT,
        ${DBTables.material} TEXT,
        ${DBTables.occasion} TEXT,
        ${DBTables.isFlashSale} INTEGER NOT NULL DEFAULT 0,
        ${DBTables.discountPercent} INTEGER NOT NULL DEFAULT 0,
        ${DBTables.freeShipping} INTEGER NOT NULL DEFAULT 0,
        ${DBTables.codAvailable} INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ==========================
    // PRODUCT TAGS TABLE
    // Many-to-many: a product can carry several tags (Handmade,
    // Customizable, Gift-Ready...) picked from a curated list.
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.productTags} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.productId} INTEGER NOT NULL,
        ${DBTables.tagValue} TEXT NOT NULL
      )
    ''');

    // ==========================
    // ORDERS TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.orders} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.customerId} INTEGER NOT NULL,
        ${DBTables.total} REAL NOT NULL,
        ${DBTables.status} TEXT NOT NULL,
        ${DBTables.orderDate} TEXT NOT NULL
      )
    ''');

    // ==========================
    // ORDER ITEMS TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.orderItems} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.orderId} INTEGER NOT NULL,
        ${DBTables.productId} INTEGER NOT NULL,
        ${DBTables.quantity} INTEGER NOT NULL,
        ${DBTables.price} REAL NOT NULL
      )
    ''');

    // ==========================
    // REVIEWS TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.reviews} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.productId} INTEGER NOT NULL,
        ${DBTables.customerId} INTEGER NOT NULL,
        ${DBTables.rating} REAL NOT NULL,
        ${DBTables.reviewComment} TEXT,
        ${DBTables.createdAt} TEXT NOT NULL
      )
    ''');

    // ==========================
    // FAVORITES TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.favorites} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.favoriteUserId} INTEGER NOT NULL,
        ${DBTables.favoriteProductId} INTEGER NOT NULL
      )
    ''');

    // ==========================
    // CART ITEMS TABLE
    // ==========================

    await db.execute('''
  CREATE TABLE ${DBTables.cartItems} (
    ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
    ${DBTables.cartUserId} INTEGER NOT NULL,
    ${DBTables.cartProductId} INTEGER NOT NULL,
    ${DBTables.quantity} INTEGER NOT NULL,
    ${DBTables.cartOptionId} TEXT NOT NULL DEFAULT '',
    ${DBTables.cartOptionName} TEXT,
    ${DBTables.cartOptionImage} TEXT,
    ${DBTables.cartUnitPrice} REAL
  )
''');

    // ==========================
    // MESSAGES TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.messages} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.senderId} INTEGER NOT NULL,
        ${DBTables.receiverId} INTEGER NOT NULL,
        ${DBTables.messageText} TEXT NOT NULL,
        ${DBTables.messageDate} TEXT NOT NULL,
        ${DBTables.isRead} INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ==========================
    // NOTIFICATIONS TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.notifications} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.notifUserId} INTEGER NOT NULL,
        ${DBTables.notifTitle} TEXT NOT NULL,
        ${DBTables.notifBody} TEXT NOT NULL,
        ${DBTables.notifType} TEXT NOT NULL,
        ${DBTables.notifRelatedId} INTEGER,
        ${DBTables.notifDate} TEXT NOT NULL,
        ${DBTables.isRead} INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ==========================
    // PRODUCT MEDIA TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.productMedia} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.mediaProductId} INTEGER NOT NULL,
        ${DBTables.mediaType} TEXT NOT NULL,
        ${DBTables.mediaPath} TEXT NOT NULL,
        ${DBTables.mediaPosition} INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ==========================
    // SHOP FOLLOWS TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.shopFollows} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.followFollowerId} INTEGER NOT NULL,
        ${DBTables.followShopId} INTEGER NOT NULL,
        ${DBTables.createdAt} TEXT NOT NULL
      )
    ''');

    // ==========================
    // SHOP VISITS TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.shopVisits} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.visitVisitorId} INTEGER NOT NULL,
        ${DBTables.visitShopId} INTEGER NOT NULL,
        ${DBTables.createdAt} TEXT NOT NULL
      )
    ''');

    // ==========================
    // DELIVERY ADDRESSES TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.deliveryAddresses} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.addressUserId} INTEGER NOT NULL,
        ${DBTables.addressFullName} TEXT NOT NULL,
        ${DBTables.addressPhone} TEXT NOT NULL,
        ${DBTables.addressLabel} TEXT NOT NULL DEFAULT 'Home',
        ${DBTables.addressLine1} TEXT NOT NULL,
        ${DBTables.addressLine2} TEXT,
        ${DBTables.addressCity} TEXT NOT NULL,
        ${DBTables.addressProvince} TEXT NOT NULL,
        ${DBTables.addressPostalCode} TEXT,
        ${DBTables.addressIsDefault} INTEGER NOT NULL DEFAULT 0,
        ${DBTables.createdAt} TEXT NOT NULL
      )
    ''');

    // ==========================
    // USER SETTINGS TABLE
    // ==========================

    await db.execute('''
      CREATE TABLE ${DBTables.userSettings} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.settingsUserId} INTEGER UNIQUE NOT NULL,
        ${DBTables.settingsPushEnabled} INTEGER NOT NULL DEFAULT 1,
        ${DBTables.settingsEmailEnabled} INTEGER NOT NULL DEFAULT 1,
        ${DBTables.settingsOrderUpdates} INTEGER NOT NULL DEFAULT 1,
        ${DBTables.settingsPromoOffers} INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // ==========================
    // VERSION 2
    // MESSAGES TABLE
    // ==========================

    if (oldVersion < 2) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DBTables.messages} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.senderId} INTEGER NOT NULL,
        ${DBTables.receiverId} INTEGER NOT NULL,
        ${DBTables.messageText} TEXT NOT NULL,
        ${DBTables.messageDate} TEXT NOT NULL,
        ${DBTables.isRead} INTEGER NOT NULL DEFAULT 0
      )
    ''');
    }

    // ==========================
    // VERSION 3
    // NOTIFICATIONS TABLE
    // ==========================

    if (oldVersion < 3) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DBTables.notifications} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.notifUserId} INTEGER NOT NULL,
        ${DBTables.notifTitle} TEXT NOT NULL,
        ${DBTables.notifBody} TEXT NOT NULL,
        ${DBTables.notifType} TEXT NOT NULL,
        ${DBTables.notifRelatedId} INTEGER,
        ${DBTables.notifDate} TEXT NOT NULL,
        ${DBTables.isRead} INTEGER NOT NULL DEFAULT 0
      )
    ''');
    }

    // ==========================
    // VERSION 4
    // PRODUCT MEDIA TABLE
    // ==========================

    if (oldVersion < 4) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DBTables.productMedia} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.mediaProductId} INTEGER NOT NULL,
        ${DBTables.mediaType} TEXT NOT NULL,
        ${DBTables.mediaPath} TEXT NOT NULL,
        ${DBTables.mediaPosition} INTEGER NOT NULL DEFAULT 0
      )
    ''');
    }

    // ==========================
    // VERSION 6
    // SHOP NAME
    // ==========================

    if (oldVersion < 6) {
      await db.execute('''
      ALTER TABLE ${DBTables.users}
      ADD COLUMN ${DBTables.shopName} TEXT
    ''');
    }

    // ==========================
    // VERSION 7
    // CATEGORY GROUPS (Category / Subcategory)
    // ==========================

    if (oldVersion < 7) {
      await db.execute('''
      ALTER TABLE ${DBTables.categories}
      ADD COLUMN ${DBTables.categoryGroup} TEXT
    ''');

      // Remove the old default categories that no product
      // currently uses, then seed the new hierarchical list.
      // Categories still referenced by an existing product are
      // left alone so nothing already listed for sale breaks.
      await db.rawDelete('''
      DELETE FROM ${DBTables.categories}
      WHERE ${DBTables.id} NOT IN (
        SELECT DISTINCT ${DBTables.categoryId} FROM ${DBTables.products}
      )
    ''');

      const newCategories = <Map<String, String>>[
        {"group": "Fiber and Textile Crafts", "name": "Knitting"},
        {"group": "Fiber and Textile Crafts", "name": "Crochet"},
        {"group": "Fiber and Textile Crafts", "name": "Sewing"},
        {"group": "Fiber and Textile Crafts", "name": "Embroidery"},
        {"group": "Fiber and Textile Crafts", "name": "Weaving"},
        {"group": "Fiber and Textile Crafts", "name": "Felting"},
        {"group": "Hard Materials and Sculpture", "name": "Woodworking"},
        {
          "group": "Hard Materials and Sculpture",
          "name": "Pottery and Ceramics",
        },
        {"group": "Hard Materials and Sculpture", "name": "Sculpting"},
        {"group": "Hard Materials and Sculpture", "name": "Leatherworking"},
        {"group": "Paper and Print Crafts", "name": "Origami"},
        {"group": "Paper and Print Crafts", "name": "Scrapbooking"},
        {"group": "Paper and Print Crafts", "name": "Calligraphy"},
        {"group": "Paper and Print Crafts", "name": "Bookbinding"},
        {"group": "Jewelry and Accessories", "name": "Beadwork"},
        {"group": "Jewelry and Accessories", "name": "Wire Wrapping"},
        {"group": "Jewelry and Accessories", "name": "Metalsmithing"},
      ];

      for (final category in newCategories) {
        await db.insert(DBTables.categories, {
          DBTables.categoryName: category["name"],
          DBTables.categoryImage: "",
          DBTables.categoryGroup: category["group"],
        });
      }
    }

    // ==========================
    // VERSION 8
    // REMOVE DEMO SELLERS / PRODUCTS
    // The app no longer seeds fake sellers or products. This cleans
    // up any demo data a device already has sitting in its local
    // database from before this change, so it disappears without
    // anyone needing to manually reset local data.
    // ==========================

    if (oldVersion < 8) {
      await db.rawDelete('''
      DELETE FROM ${DBTables.products}
      WHERE ${DBTables.sellerId} IN (
        SELECT ${DBTables.id} FROM ${DBTables.users}
        WHERE ${DBTables.email} LIKE '%@craftofove.local'
      )
    ''');

      await db.rawDelete('''
      DELETE FROM ${DBTables.users}
      WHERE ${DBTables.email} LIKE '%@craftofove.local'
    ''');
    }

    // ==========================
    // VERSION 9
    // PRODUCT TAXONOMY (Craft Type / Material / Occasion / Tags)
    // Categories are restructured from a flat craft-technique list
    // into Main Category + Subcategory (still stored as
    // category_group / name on the categories table — no schema
    // change needed there). Per the app owner, no real products
    // exist yet, so this also clears products/categories/tags and
    // lets SeedData repopulate the new category list from scratch.
    // ==========================

    if (oldVersion < 9) {
      await db.execute('''
      ALTER TABLE ${DBTables.products} ADD COLUMN ${DBTables.craftType} TEXT
    ''');
      await db.execute('''
      ALTER TABLE ${DBTables.products} ADD COLUMN ${DBTables.material} TEXT
    ''');
      await db.execute('''
      ALTER TABLE ${DBTables.products} ADD COLUMN ${DBTables.occasion} TEXT
    ''');

      await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DBTables.productTags} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.productId} INTEGER NOT NULL,
        ${DBTables.tagValue} TEXT NOT NULL
      )
    ''');

      await db.rawDelete('DELETE FROM ${DBTables.productTags}');
      await db.rawDelete('DELETE FROM ${DBTables.productMedia}');
      await db.rawDelete('DELETE FROM ${DBTables.cartItems}');
      await db.rawDelete('DELETE FROM ${DBTables.favorites}');
      await db.rawDelete('DELETE FROM ${DBTables.reviews}');
      await db.rawDelete('DELETE FROM ${DBTables.orderItems}');
      await db.rawDelete('DELETE FROM ${DBTables.orders}');
      await db.rawDelete('DELETE FROM ${DBTables.products}');
      await db.rawDelete('DELETE FROM ${DBTables.categories}');
    }

    // ==========================
    // VERSION 10
    // SHOP PROFILE (Flash Sale flag + Follow Shop table)
    // Powers the customer-facing "visit the shop" screen: shops can
    // flag products as part of a flash sale, and customers can
    // follow a shop.
    // ==========================

    if (oldVersion < 10) {
      await db.execute('''
      ALTER TABLE ${DBTables.products}
      ADD COLUMN ${DBTables.isFlashSale} INTEGER NOT NULL DEFAULT 0
    ''');

      await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DBTables.shopFollows} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.followFollowerId} INTEGER NOT NULL,
        ${DBTables.followShopId} INTEGER NOT NULL,
        ${DBTables.createdAt} TEXT NOT NULL
      )
    ''');
    }

    // ==========================
    // VERSION 11
    // SHOP APPEARANCE (cover photo + profile photo)
    // Lets a seller upload their own cover banner and profile
    // picture for their shop page, instead of the page falling
    // back to a product photo or initials.
    // ==========================

    if (oldVersion < 11) {
      await db.execute('''
      ALTER TABLE ${DBTables.users} ADD COLUMN ${DBTables.coverImage} TEXT
    ''');
      await db.execute('''
      ALTER TABLE ${DBTables.users} ADD COLUMN ${DBTables.profileImage} TEXT
    ''');
    }

    // ==========================
    // VERSION 12
    // PRODUCT MERCHANDISING (Discount % + Free Shipping + COD)
    // Lets a seller flag a discount percentage and whether a
    // product ships free / supports Cash on Delivery, so the
    // customer product card can badge these on the listing.
    // ==========================

    if (oldVersion < 12) {
      await db.execute('''
      ALTER TABLE ${DBTables.products}
      ADD COLUMN ${DBTables.discountPercent} INTEGER NOT NULL DEFAULT 0
    ''');
      await db.execute('''
      ALTER TABLE ${DBTables.products}
      ADD COLUMN ${DBTables.freeShipping} INTEGER NOT NULL DEFAULT 0
    ''');
      await db.execute('''
      ALTER TABLE ${DBTables.products}
      ADD COLUMN ${DBTables.codAvailable} INTEGER NOT NULL DEFAULT 0
    ''');
    }

    // ==========================
    // VERSION 13
    // SHOP LIVE STATUS
    // Lets a seller flag their shop as currently live, so followers
    // see a red "live" ring around the shop's avatar in the
    // customer app's Messages "Following" row.
    // ==========================

    if (oldVersion < 13) {
      await db.execute('''
      ALTER TABLE ${DBTables.users}
      ADD COLUMN ${DBTables.isLive} INTEGER NOT NULL DEFAULT 0
    ''');
    }

    // ==========================
    // VERSION 14
    // SHOP VISITS TABLE
    // Logs each time a customer opens a seller's shop page, so the
    // seller profile can show a "visitors" count (distinct
    // customers who've viewed the shop).
    // ==========================

    if (oldVersion < 14) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DBTables.shopVisits} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.visitVisitorId} INTEGER NOT NULL,
        ${DBTables.visitShopId} INTEGER NOT NULL,
        ${DBTables.createdAt} TEXT NOT NULL
      )
    ''');
    }

    // ==========================
    // VERSION 15
    // DELIVERY ADDRESSES + USER SETTINGS + FAVORITES USAGE
    // Powers the customer Profile menu: Personal Information edits,
    // saved delivery addresses, per-user notification settings, and
    // makes the (already-existing but unused) favorites table
    // actually readable/writable from the app.
    // ==========================

    if (oldVersion < 15) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DBTables.deliveryAddresses} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.addressUserId} INTEGER NOT NULL,
        ${DBTables.addressFullName} TEXT NOT NULL,
        ${DBTables.addressPhone} TEXT NOT NULL,
        ${DBTables.addressLabel} TEXT NOT NULL DEFAULT 'Home',
        ${DBTables.addressLine1} TEXT NOT NULL,
        ${DBTables.addressLine2} TEXT,
        ${DBTables.addressCity} TEXT NOT NULL,
        ${DBTables.addressProvince} TEXT NOT NULL,
        ${DBTables.addressPostalCode} TEXT,
        ${DBTables.addressIsDefault} INTEGER NOT NULL DEFAULT 0,
        ${DBTables.createdAt} TEXT NOT NULL
      )
    ''');

      await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DBTables.userSettings} (
        ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBTables.settingsUserId} INTEGER UNIQUE NOT NULL,
        ${DBTables.settingsPushEnabled} INTEGER NOT NULL DEFAULT 1,
        ${DBTables.settingsEmailEnabled} INTEGER NOT NULL DEFAULT 1,
        ${DBTables.settingsOrderUpdates} INTEGER NOT NULL DEFAULT 1,
        ${DBTables.settingsPromoOffers} INTEGER NOT NULL DEFAULT 1
      )
    ''');
    }

    if (oldVersion < 16) {
      await db.execute(
        'ALTER TABLE ${DBTables.cartItems} ADD COLUMN ${DBTables.cartOptionId} TEXT NOT NULL DEFAULT \'\'',
      );
      await db.execute(
        'ALTER TABLE ${DBTables.cartItems} ADD COLUMN ${DBTables.cartOptionName} TEXT',
      );
      await db.execute(
        'ALTER TABLE ${DBTables.cartItems} ADD COLUMN ${DBTables.cartOptionImage} TEXT',
      );
      await db.execute(
        'ALTER TABLE ${DBTables.cartItems} ADD COLUMN ${DBTables.cartUnitPrice} REAL',
      );
    }

    // ==========================
    // VERSION 17
    // REMOVE LOCAL PASSWORD STORAGE
    // Firebase Auth is the only credential store. Rebuilding the table
    // permanently removes plaintext passwords from existing installations.
    // ==========================

    if (oldVersion < 17) {
      const secureUsersTable = 'users_v17_secure';
      await db.execute('DROP TABLE IF EXISTS $secureUsersTable');
      await db.execute('''
        CREATE TABLE $secureUsersTable (
          ${DBTables.id} INTEGER PRIMARY KEY AUTOINCREMENT,
          ${DBTables.firstName} TEXT NOT NULL,
          ${DBTables.lastName} TEXT NOT NULL,
          ${DBTables.email} TEXT UNIQUE NOT NULL,
          ${DBTables.phone} TEXT,
          ${DBTables.accountType} TEXT NOT NULL,
          ${DBTables.shopName} TEXT,
          ${DBTables.coverImage} TEXT,
          ${DBTables.profileImage} TEXT,
          ${DBTables.isLive} INTEGER NOT NULL DEFAULT 0,
          ${DBTables.createdAt} TEXT NOT NULL
        )
      ''');
      await db.execute('''
        INSERT INTO $secureUsersTable (
          ${DBTables.id},
          ${DBTables.firstName},
          ${DBTables.lastName},
          ${DBTables.email},
          ${DBTables.phone},
          ${DBTables.accountType},
          ${DBTables.shopName},
          ${DBTables.coverImage},
          ${DBTables.profileImage},
          ${DBTables.isLive},
          ${DBTables.createdAt}
        )
        SELECT
          ${DBTables.id},
          ${DBTables.firstName},
          ${DBTables.lastName},
          ${DBTables.email},
          ${DBTables.phone},
          ${DBTables.accountType},
          ${DBTables.shopName},
          ${DBTables.coverImage},
          ${DBTables.profileImage},
          ${DBTables.isLive},
          ${DBTables.createdAt}
        FROM ${DBTables.users}
      ''');
      await db.execute('DROP TABLE ${DBTables.users}');
      await db.execute(
        'ALTER TABLE $secureUsersTable RENAME TO ${DBTables.users}',
      );
    }
  }

  // ==========================
  // REGISTER USER
  // ==========================

  Future<int> registerUser(Map<String, dynamic> user) async {
    final db = await database;

    return await db.insert(
      DBTables.users,
      user,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // ==========================
  // GET USER BY EMAIL
  // ==========================

  Future<UserModel?> getUserByEmail(String email) async {
    final db = await database;

    final result = await db.query(
      DBTables.users,
      where: '${DBTables.email} = ?',
      whereArgs: [email],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return UserModel.fromMap(result.first);
    }

    return null;
  }

  // ==========================
  // GET USER BY ID
  // ==========================

  Future<UserModel?> getUserById(int id) async {
    final db = await database;

    final result = await db.query(
      DBTables.users,
      where: '${DBTables.id} = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return UserModel.fromMap(result.first);
    }

    return null;
  }

  // ==========================
  // UPDATE SHOP APPEARANCE (cover photo / profile photo)
  // ==========================

  Future<int> updateShopImages(
    int userId, {
    String? coverImage,
    String? profileImage,
  }) async {
    final db = await database;

    final values = <String, dynamic>{};
    if (coverImage != null) values[DBTables.coverImage] = coverImage;
    if (profileImage != null) values[DBTables.profileImage] = profileImage;

    if (values.isEmpty) return 0;

    return await db.update(
      DBTables.users,
      values,
      where: '${DBTables.id} = ?',
      whereArgs: [userId],
    );
  }

  // ==========================
  // CATEGORY METHODS
  // ==========================

  Future<int> insertCategory(Map<String, dynamic> category) async {
    final db = await database;

    return await db.insert(DBTables.categories, category);
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await database;

    final result = await db.query(
      DBTables.categories,
      orderBy: DBTables.categoryName,
    );

    debugPrint("CATEGORIES:");
    debugPrint(result.toString());

    return result;
  }

  // ==========================
  // PRODUCT METHODS
  // ==========================

  Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await database;

    return await db.insert(DBTables.products, product);
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await database;

    final result = await db.query(
      DBTables.products,
      orderBy: "${DBTables.id} DESC",
    );

    debugPrint("PRODUCTS:");
    debugPrint(result.toString());

    return result;
  }

  /// Same as [getProducts], but excludes listings that belong to the
  /// built-in demo/seed sellers (see SeedData) so customers only ever
  /// browse products a real seller actually uploaded. Cart/checkout
  /// still use [getProducts] so an existing cart never loses a lookup.
  Future<List<Map<String, dynamic>>> getRealSellerProducts() async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT p.* FROM ${DBTables.products} p
      INNER JOIN ${DBTables.users} u
        ON u.${DBTables.id} = p.${DBTables.sellerId}
      WHERE u.${DBTables.email} NOT LIKE '%@craftofove.local'
      ORDER BY p.${DBTables.id} DESC
    ''');

    debugPrint("REAL SELLER PRODUCTS:");
    debugPrint(result.toString());

    return result;
  }

  /// [getRealSellerProducts] narrowed down to a single category, for
  /// the Categories tab's "browse by category" drill-down.
  Future<List<Map<String, dynamic>>> getRealSellerProductsByCategory(
    int categoryId,
  ) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT p.* FROM ${DBTables.products} p
      INNER JOIN ${DBTables.users} u
        ON u.${DBTables.id} = p.${DBTables.sellerId}
      WHERE u.${DBTables.email} NOT LIKE '%@craftofove.local'
        AND p.${DBTables.categoryId} = ?
      ORDER BY p.${DBTables.id} DESC
    ''',
      [categoryId],
    );

    debugPrint("REAL SELLER PRODUCTS FOR CATEGORY $categoryId:");
    debugPrint(result.toString());

    return result;
  }

  /// [getRealSellerProducts] narrowed by any combination of the
  /// product taxonomy fields. Pass only the filters that apply —
  /// null ones are ignored. [mainCategory] and [subcategory] match
  /// against the categories table's group/name (a product's
  /// category_id joins to exactly one category row), while
  /// [craftType], [material], and [occasion] match the product's own
  /// columns, and [tag] matches against product_tags.
  Future<List<Map<String, dynamic>>> getFilteredRealSellerProducts({
    String? mainCategory,
    String? subcategory,
    String? craftType,
    String? material,
    String? occasion,
    String? tag,
  }) async {
    final db = await database;

    final where = <String>["u.${DBTables.email} NOT LIKE '%@craftofove.local'"];
    final args = <Object?>[];

    if (mainCategory != null) {
      where.add("c.${DBTables.categoryGroup} = ?");
      args.add(mainCategory);
    }
    if (subcategory != null) {
      where.add("c.${DBTables.categoryName} = ?");
      args.add(subcategory);
    }
    if (craftType != null) {
      where.add("p.${DBTables.craftType} = ?");
      args.add(craftType);
    }
    if (material != null) {
      where.add("p.${DBTables.material} = ?");
      args.add(material);
    }
    if (occasion != null) {
      where.add("p.${DBTables.occasion} = ?");
      args.add(occasion);
    }

    final tagJoin = tag != null
        ? "INNER JOIN ${DBTables.productTags} t ON t.${DBTables.productId} = p.${DBTables.id}"
        : "";
    if (tag != null) {
      where.add("t.${DBTables.tagValue} = ?");
      args.add(tag);
    }

    final result = await db.rawQuery('''
      SELECT DISTINCT p.* FROM ${DBTables.products} p
      INNER JOIN ${DBTables.users} u
        ON u.${DBTables.id} = p.${DBTables.sellerId}
      INNER JOIN ${DBTables.categories} c
        ON c.${DBTables.id} = p.${DBTables.categoryId}
      $tagJoin
      WHERE ${where.join(' AND ')}
      ORDER BY p.${DBTables.id} DESC
    ''', args);

    debugPrint("FILTERED REAL SELLER PRODUCTS:");
    debugPrint(result.toString());

    return result;
  }

  Future<List<Map<String, dynamic>>> getProductsBySeller(int sellerId) async {
    final db = await database;

    final result = await db.query(
      DBTables.products,
      where: "${DBTables.sellerId} = ?",
      whereArgs: [sellerId],
      orderBy: "${DBTables.id} DESC",
    );

    return result;
  }

  Future<int> updateProduct(int id, Map<String, dynamic> product) async {
    final db = await database;

    return await db.update(
      DBTables.products,
      product,
      where: "${DBTables.id} = ?",
      whereArgs: [id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;

    // Clean up any media and tag rows tied to this product first.
    await db.delete(
      DBTables.productMedia,
      where: "${DBTables.mediaProductId} = ?",
      whereArgs: [id],
    );
    await db.delete(
      DBTables.productTags,
      where: "${DBTables.productId} = ?",
      whereArgs: [id],
    );

    return await db.delete(
      DBTables.products,
      where: "${DBTables.id} = ?",
      whereArgs: [id],
    );
  }

  // ==========================
  // PRODUCT TAG METHODS
  // ==========================

  Future<void> insertProductTags(int productId, List<String> tags) async {
    final db = await database;

    for (final tag in tags) {
      await db.insert(DBTables.productTags, {
        DBTables.productId: productId,
        DBTables.tagValue: tag,
      });
    }
  }

  /// Replaces a product's full tag set — used by both add (nothing to
  /// replace yet) and edit (clears the old set first).
  Future<void> replaceProductTags(int productId, List<String> tags) async {
    final db = await database;

    await db.delete(
      DBTables.productTags,
      where: "${DBTables.productId} = ?",
      whereArgs: [productId],
    );

    await insertProductTags(productId, tags);
  }

  Future<List<String>> getProductTags(int productId) async {
    final db = await database;

    final result = await db.query(
      DBTables.productTags,
      columns: [DBTables.tagValue],
      where: "${DBTables.productId} = ?",
      whereArgs: [productId],
    );

    return result.map((row) => row[DBTables.tagValue] as String).toList();
  }

  // ==========================
  // PRODUCT MEDIA METHODS
  // ==========================

  Future<void> insertProductMedia(Map<String, dynamic> media) async {
    final db = await database;
    await db.insert(DBTables.productMedia, media);
  }

  Future<List<Map<String, dynamic>>> getMediaForProduct(int productId) async {
    final db = await database;

    return await db.query(
      DBTables.productMedia,
      where: "${DBTables.mediaProductId} = ?",
      whereArgs: [productId],
      orderBy: "${DBTables.mediaPosition} ASC",
    );
  }

  /// Replaces all media for a product with a new set — used when a
  /// seller edits a product's photos/videos.
  Future<void> replaceProductMedia(
    int productId,
    List<Map<String, dynamic>> mediaRows,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete(
        DBTables.productMedia,
        where: "${DBTables.mediaProductId} = ?",
        whereArgs: [productId],
      );

      for (final row in mediaRows) {
        await txn.insert(DBTables.productMedia, row);
      }
    });
  }

  // ==========================
  // SELLER ORDER METHODS
  // ==========================

  /// Returns one row per order item belonging to this seller's products,
  /// joined with the parent order, the product, and the buyer — newest first.
  Future<List<Map<String, dynamic>>> getOrderItemsForSeller(
    int sellerId,
  ) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT
        oi.${DBTables.id} AS item_id,
        oi.${DBTables.orderId} AS order_id,
        oi.${DBTables.productId} AS product_id,
        oi.${DBTables.quantity} AS quantity,
        oi.${DBTables.price} AS item_price,
        o.${DBTables.status} AS status,
        o.${DBTables.orderDate} AS order_date,
        o.${DBTables.customerId} AS customer_id,
        p.${DBTables.productName} AS product_name,
        p.${DBTables.image} AS product_image,
        u.${DBTables.firstName} AS customer_first_name,
        u.${DBTables.lastName} AS customer_last_name
      FROM ${DBTables.orderItems} oi
      INNER JOIN ${DBTables.orders} o ON oi.${DBTables.orderId} = o.${DBTables.id}
      INNER JOIN ${DBTables.products} p ON oi.${DBTables.productId} = p.${DBTables.id}
      LEFT JOIN ${DBTables.users} u ON o.${DBTables.customerId} = u.${DBTables.id}
      WHERE p.${DBTables.sellerId} = ?
      ORDER BY o.${DBTables.orderDate} DESC
    ''',
      [sellerId],
    );

    return result;
  }

  Future<int> updateOrderStatus(int orderId, String status) async {
    final db = await database;

    return await db.update(
      DBTables.orders,
      {DBTables.status: status},
      where: "${DBTables.id} = ?",
      whereArgs: [orderId],
    );
  }

  /// Returns one row per order item belonging to this customer's own
  /// orders, joined with the product and its seller — newest first.
  Future<List<Map<String, dynamic>>> getOrderItemsForCustomer(
    int customerId,
  ) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT
        oi.${DBTables.id} AS item_id,
        oi.${DBTables.orderId} AS order_id,
        oi.${DBTables.productId} AS product_id,
        oi.${DBTables.quantity} AS quantity,
        oi.${DBTables.price} AS item_price,
        o.${DBTables.status} AS status,
        o.${DBTables.orderDate} AS order_date,
        p.${DBTables.productName} AS product_name,
        p.${DBTables.image} AS product_image,
        p.${DBTables.sellerId} AS seller_id,
        u.${DBTables.firstName} AS seller_first_name,
        u.${DBTables.lastName} AS seller_last_name
      FROM ${DBTables.orderItems} oi
      INNER JOIN ${DBTables.orders} o ON oi.${DBTables.orderId} = o.${DBTables.id}
      LEFT JOIN ${DBTables.products} p ON oi.${DBTables.productId} = p.${DBTables.id}
      LEFT JOIN ${DBTables.users} u ON p.${DBTables.sellerId} = u.${DBTables.id}
      WHERE o.${DBTables.customerId} = ?
      ORDER BY o.${DBTables.orderDate} DESC
    ''',
      [customerId],
    );

    return result;
  }

  // ==========================
  // GET CART TOTAL QUANTITY
  // ==========================

  // ==========================
  // CART METHODS
  // ==========================

  Future<int> addToCart(
    int userId,
    int productId,
    int quantity, {
    String? optionId,
    String? optionName,
    String? optionImage,
    double? unitPrice,
  }) async {
    final db = await database;
    final normalizedOptionId = optionId ?? '';

    final existing = await db.query(
      DBTables.cartItems,
      where:
          '${DBTables.cartUserId} = ? AND ${DBTables.cartProductId} = ? AND ${DBTables.cartOptionId} = ?',
      whereArgs: [userId, productId, normalizedOptionId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final cartId = existing.first[DBTables.id] as int;
      final currentQuantity = existing.first[DBTables.quantity] as int;

      return await db.update(
        DBTables.cartItems,
        {DBTables.quantity: currentQuantity + quantity},
        where: '${DBTables.id} = ?',
        whereArgs: [cartId],
      );
    }

    return await db.insert(DBTables.cartItems, {
      DBTables.cartUserId: userId,
      DBTables.cartProductId: productId,
      DBTables.quantity: quantity,
      DBTables.cartOptionId: normalizedOptionId,
      DBTables.cartOptionName: optionName,
      DBTables.cartOptionImage: optionImage,
      DBTables.cartUnitPrice: unitPrice,
    });
  }

  Future<List<CartItemModel>> getCartItems(int userId) async {
    final db = await database;

    final result = await db.query(
      DBTables.cartItems,
      where: '${DBTables.cartUserId} = ?',
      whereArgs: [userId],
      orderBy: '${DBTables.id} DESC',
    );

    return result.map((item) => CartItemModel.fromMap(item)).toList();
  }

  Future<int> updateCartQuantity(int cartId, int quantity) async {
    final db = await database;

    return await db.update(
      DBTables.cartItems,
      {DBTables.quantity: quantity},
      where: '${DBTables.id} = ?',
      whereArgs: [cartId],
    );
  }

  Future<int> removeFromCart(int cartId) async {
    final db = await database;

    return await db.delete(
      DBTables.cartItems,
      where: '${DBTables.id} = ?',
      whereArgs: [cartId],
    );
  }

  Future<int> clearCart(int userId) async {
    final db = await database;

    return await db.delete(
      DBTables.cartItems,
      where: '${DBTables.cartUserId} = ?',
      whereArgs: [userId],
    );
  }

  // ==========================
  // CHECKOUT / ORDER CREATION
  // ==========================

  /// Creates the order, its line items, and decrements product stock —
  /// all inside one transaction, so a checkout never partially completes.
  /// Does NOT clear the cart; call [clearCart] separately after success.
  Future<int> placeOrder({
    required int customerId,
    required double total,
    required List<CartItemModel> cartItems,
    required Map<int, double> priceByProductId,
  }) async {
    final db = await database;

    return await db.transaction<int>((txn) async {
      final orderId = await txn.insert(DBTables.orders, {
        DBTables.customerId: customerId,
        DBTables.total: total,
        DBTables.status: "Pending",
        DBTables.orderDate: DateTime.now().toIso8601String(),
      });

      for (final item in cartItems) {
        final price = priceByProductId[item.productId] ?? 0;

        await txn.insert(DBTables.orderItems, {
          DBTables.orderId: orderId,
          DBTables.productId: item.productId,
          DBTables.quantity: item.quantity,
          DBTables.price: price,
        });

        await txn.rawUpdate(
          '''
          UPDATE ${DBTables.products}
          SET ${DBTables.stock} = MAX(${DBTables.stock} - ?, 0)
          WHERE ${DBTables.id} = ?
          ''',
          [item.quantity, item.productId],
        );
      }

      return orderId;
    });
  }

  Future<int> getCartItemCount(int userId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
    SELECT COALESCE(SUM(${DBTables.quantity}), 0) AS total
    FROM ${DBTables.cartItems}
    WHERE ${DBTables.cartUserId} = ?
    ''',
      [userId],
    );

    return (result.first['total'] as int?) ?? 0;
  }

  // ==========================
  // REVIEWS
  // ==========================

  Future<Map<String, dynamic>?> getReviewByCustomerForProduct(
    int productId,
    int customerId,
  ) async {
    final db = await database;

    final result = await db.query(
      DBTables.reviews,
      where: "${DBTables.productId} = ? AND ${DBTables.customerId} = ?",
      whereArgs: [productId, customerId],
      limit: 1,
    );

    return result.isEmpty ? null : result.first;
  }

  /// Whether this customer has a Delivered order containing this
  /// product — used to gate who is allowed to leave a rating.
  Future<bool> hasDeliveredOrderForProduct(
    int customerId,
    int productId,
  ) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT oi.${DBTables.id}
      FROM ${DBTables.orderItems} oi
      INNER JOIN ${DBTables.orders} o ON oi.${DBTables.orderId} = o.${DBTables.id}
      WHERE o.${DBTables.customerId} = ?
        AND oi.${DBTables.productId} = ?
        AND o.${DBTables.status} = 'Delivered'
      LIMIT 1
    ''',
      [customerId, productId],
    );

    return result.isNotEmpty;
  }

  /// Inserts a new review, or updates the customer's existing review
  /// for this product, then refreshes the product's stored average
  /// rating so it stays in sync without a live join everywhere.
  Future<void> upsertReview({
    required int productId,
    required int customerId,
    required double rating,
    String? comment,
  }) async {
    final db = await database;

    final existing = await getReviewByCustomerForProduct(productId, customerId);

    if (existing == null) {
      await db.insert(DBTables.reviews, {
        DBTables.productId: productId,
        DBTables.customerId: customerId,
        DBTables.rating: rating,
        DBTables.reviewComment: comment,
        DBTables.createdAt: DateTime.now().toIso8601String(),
      });
    } else {
      await db.update(
        DBTables.reviews,
        {
          DBTables.rating: rating,
          DBTables.reviewComment: comment,
          DBTables.createdAt: DateTime.now().toIso8601String(),
        },
        where: "${DBTables.id} = ?",
        whereArgs: [existing[DBTables.id]],
      );
    }

    final summary = await db.rawQuery(
      '''
      SELECT AVG(${DBTables.rating}) AS avg_rating
      FROM ${DBTables.reviews}
      WHERE ${DBTables.productId} = ?
    ''',
      [productId],
    );

    final avgRating = (summary.first['avg_rating'] as num?)?.toDouble() ?? 0;

    await db.update(
      DBTables.products,
      {DBTables.rating: avgRating},
      where: "${DBTables.id} = ?",
      whereArgs: [productId],
    );
  }

  /// All reviews for a product, newest first, joined with the
  /// reviewer's name.
  Future<List<Map<String, dynamic>>> getReviewsForProduct(int productId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT
        r.${DBTables.id} AS id,
        r.${DBTables.productId} AS product_id,
        r.${DBTables.customerId} AS customer_id,
        r.${DBTables.rating} AS rating,
        r.${DBTables.reviewComment} AS comment,
        r.${DBTables.createdAt} AS created_at,
        u.${DBTables.firstName} AS customer_first_name,
        u.${DBTables.lastName} AS customer_last_name
      FROM ${DBTables.reviews} r
      LEFT JOIN ${DBTables.users} u ON r.${DBTables.customerId} = u.${DBTables.id}
      WHERE r.${DBTables.productId} = ?
      ORDER BY r.${DBTables.createdAt} DESC
    ''',
      [productId],
    );

    return result;
  }

  /// Average rating + review count for a product.
  Future<Map<String, dynamic>> getProductRatingSummary(int productId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT
        AVG(${DBTables.rating}) AS average,
        COUNT(*) AS count
      FROM ${DBTables.reviews}
      WHERE ${DBTables.productId} = ?
    ''',
      [productId],
    );

    final row = result.first;

    return {
      "average": (row["average"] as num?)?.toDouble() ?? 0,
      "count": (row["count"] as num?)?.toInt() ?? 0,
    };
  }

  // ==========================
  // SALES STATS
  // ==========================

  /// Total quantity sold per product for this seller (one row per
  /// product, 0 sales included) — powers the seller dashboard's
  /// "most sold" info. Cancelled orders don't count as sales.
  Future<List<Map<String, dynamic>>> getSellerProductSales(int sellerId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT
        p.${DBTables.id} AS product_id,
        COALESCE(SUM(
          CASE WHEN o.${DBTables.status} = 'Cancelled' THEN 0
               ELSE oi.${DBTables.quantity} END
        ), 0) AS total_sold
      FROM ${DBTables.products} p
      LEFT JOIN ${DBTables.orderItems} oi ON oi.${DBTables.productId} = p.${DBTables.id}
      LEFT JOIN ${DBTables.orders} o ON oi.${DBTables.orderId} = o.${DBTables.id}
      WHERE p.${DBTables.sellerId} = ?
      GROUP BY p.${DBTables.id}
    ''',
      [sellerId],
    );

    return result;
  }

  /// Total quantity ever sold per product, across every real
  /// seller's listing (0 sales included) — powers the "sold" count
  /// shown on each product card throughout the customer app.
  /// Cancelled orders don't count as sales.
  Future<List<Map<String, dynamic>>> getAllProductSales() async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT
        p.${DBTables.id} AS product_id,
        COALESCE(SUM(
          CASE WHEN o.${DBTables.status} = 'Cancelled' THEN 0
               ELSE oi.${DBTables.quantity} END
        ), 0) AS total_sold
      FROM ${DBTables.products} p
      INNER JOIN ${DBTables.users} u ON u.${DBTables.id} = p.${DBTables.sellerId}
      LEFT JOIN ${DBTables.orderItems} oi ON oi.${DBTables.productId} = p.${DBTables.id}
      LEFT JOIN ${DBTables.orders} o ON oi.${DBTables.orderId} = o.${DBTables.id}
      WHERE u.${DBTables.email} NOT LIKE '%@craftofove.local'
      GROUP BY p.${DBTables.id}
    ''');

    return result;
  }

  /// Real-seller products sold the most this calendar month —
  /// powers the customer home screen's "Best Sellers This Month".
  Future<List<Map<String, dynamic>>> getBestSellingProductsThisMonth({
    int limit = 10,
  }) async {
    final db = await database;

    final now = DateTime.now();
    final monthPrefix =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}";

    final result = await db.rawQuery(
      '''
      SELECT
        p.*,
        SUM(oi.${DBTables.quantity}) AS total_sold
      FROM ${DBTables.orderItems} oi
      INNER JOIN ${DBTables.orders} o ON oi.${DBTables.orderId} = o.${DBTables.id}
      INNER JOIN ${DBTables.products} p ON oi.${DBTables.productId} = p.${DBTables.id}
      INNER JOIN ${DBTables.users} u ON p.${DBTables.sellerId} = u.${DBTables.id}
      WHERE o.${DBTables.status} != 'Cancelled'
        AND substr(o.${DBTables.orderDate}, 1, 7) = ?
        AND u.${DBTables.email} NOT LIKE '%@craftofove.local'
      GROUP BY p.${DBTables.id}
      ORDER BY total_sold DESC
      LIMIT ?
    ''',
      [monthPrefix, limit],
    );

    return result;
  }

  // ==========================
  // SHOP PROFILE
  // ==========================

  /// Real-seller products belonging to [sellerId] that are flagged
  /// as part of a flash sale — powers the shop's Home tab.
  Future<List<Map<String, dynamic>>> getFlashSaleProductsForSeller(
    int sellerId,
  ) async {
    final db = await database;

    final result = await db.query(
      DBTables.products,
      where: "${DBTables.sellerId} = ? AND ${DBTables.isFlashSale} = 1",
      whereArgs: [sellerId],
      orderBy: "${DBTables.id} DESC",
    );

    return result;
  }

  /// Average rating + review count across every product a shop
  /// sells — powers the shop rating shown on its profile.
  Future<Map<String, dynamic>> getShopRatingSummary(int sellerId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT
        AVG(r.${DBTables.rating}) AS average,
        COUNT(*) AS count
      FROM ${DBTables.reviews} r
      INNER JOIN ${DBTables.products} p ON p.${DBTables.id} = r.${DBTables.productId}
      WHERE p.${DBTables.sellerId} = ?
    ''',
      [sellerId],
    );

    final row = result.first;

    return {
      "average": (row["average"] as num?)?.toDouble() ?? 0,
      "count": (row["count"] as num?)?.toInt() ?? 0,
    };
  }

  /// Total units sold across every product a shop sells (cancelled
  /// orders excluded) — powers the "X sold" stat on the shop profile.
  Future<int> getShopTotalSold(int sellerId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(
        CASE WHEN o.${DBTables.status} = 'Cancelled' THEN 0
             ELSE oi.${DBTables.quantity} END
      ), 0) AS total_sold
      FROM ${DBTables.products} p
      LEFT JOIN ${DBTables.orderItems} oi ON oi.${DBTables.productId} = p.${DBTables.id}
      LEFT JOIN ${DBTables.orders} o ON oi.${DBTables.orderId} = o.${DBTables.id}
      WHERE p.${DBTables.sellerId} = ?
    ''',
      [sellerId],
    );

    return (result.first["total_sold"] as num?)?.toInt() ?? 0;
  }

  /// How many customers currently follow this shop.
  Future<int> getShopFollowerCount(int sellerId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${DBTables.shopFollows}
      WHERE ${DBTables.followShopId} = ?
    ''',
      [sellerId],
    );

    return (result.first["total"] as num?)?.toInt() ?? 0;
  }

  /// Logs that [visitorId] opened [sellerId]'s shop page. Safe to
  /// call on every visit — a customer can rack up several visit
  /// rows over time, but the "visitors" count below only counts
  /// each customer once.
  Future<void> recordShopVisit(int visitorId, int sellerId) async {
    final db = await database;

    await db.insert(DBTables.shopVisits, {
      DBTables.visitVisitorId: visitorId,
      DBTables.visitShopId: sellerId,
      DBTables.createdAt: DateTime.now().toIso8601String(),
    });
  }

  /// How many distinct customers have ever visited this shop.
  Future<int> getShopVisitorCount(int sellerId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT ${DBTables.visitVisitorId}) AS total
      FROM ${DBTables.shopVisits}
      WHERE ${DBTables.visitShopId} = ?
    ''',
      [sellerId],
    );

    return (result.first["total"] as num?)?.toInt() ?? 0;
  }

  /// Whether [followerId] currently follows [sellerId]'s shop.
  Future<bool> isFollowingShop(int followerId, int sellerId) async {
    final db = await database;

    final result = await db.query(
      DBTables.shopFollows,
      where:
          "${DBTables.followFollowerId} = ? AND ${DBTables.followShopId} = ?",
      whereArgs: [followerId, sellerId],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  /// Follows a shop if not already followed; unfollows it otherwise.
  /// Returns the new follow state.
  Future<bool> toggleFollowShop(int followerId, int sellerId) async {
    final db = await database;

    final existing = await db.query(
      DBTables.shopFollows,
      where:
          "${DBTables.followFollowerId} = ? AND ${DBTables.followShopId} = ?",
      whereArgs: [followerId, sellerId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await db.delete(
        DBTables.shopFollows,
        where: "${DBTables.id} = ?",
        whereArgs: [existing.first[DBTables.id]],
      );
      return false;
    }

    await db.insert(DBTables.shopFollows, {
      DBTables.followFollowerId: followerId,
      DBTables.followShopId: sellerId,
      DBTables.createdAt: DateTime.now().toIso8601String(),
    });
    return true;
  }

  /// Every shop [followerId] follows, newest-followed first — each
  /// row is the seller's full user record (name, shop name, avatar,
  /// live status), for the "Following" story row on the Messages
  /// screen.
  Future<List<Map<String, dynamic>>> getFollowedShops(int followerId) async {
    final db = await database;

    return db.rawQuery(
      '''
      SELECT u.*
      FROM ${DBTables.shopFollows} f
      INNER JOIN ${DBTables.users} u ON u.${DBTables.id} = f.${DBTables.followShopId}
      WHERE f.${DBTables.followFollowerId} = ?
      ORDER BY f.${DBTables.id} DESC
    ''',
      [followerId],
    );
  }

  /// Sets whether [sellerId]'s shop is currently live, for the red
  /// "live" ring shown on their avatar to followers.
  Future<void> setSellerLiveStatus(int sellerId, bool isLive) async {
    final db = await database;

    await db.update(
      DBTables.users,
      {DBTables.isLive: isLive ? 1 : 0},
      where: "${DBTables.id} = ?",
      whereArgs: [sellerId],
    );
  }

  // ==========================
  // PROFILE (Personal Information)
  // ==========================

  /// Updates whichever of these fields are provided for [userId].
  /// Returns "success", or an error message ("Email already in use")
  /// if the new email collides with a different account.
  Future<String> updateUserProfile(
    int userId, {
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
  }) async {
    final db = await database;

    final values = <String, dynamic>{};

    if (firstName != null) values[DBTables.firstName] = firstName.trim();
    if (lastName != null) values[DBTables.lastName] = lastName.trim();
    if (phone != null) values[DBTables.phone] = phone.trim();

    if (email != null) {
      final cleanEmail = email.trim().toLowerCase();

      final existing = await db.query(
        DBTables.users,
        where: '${DBTables.email} = ? AND ${DBTables.id} != ?',
        whereArgs: [cleanEmail, userId],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        return "Email already in use";
      }

      values[DBTables.email] = cleanEmail;
    }

    if (values.isEmpty) return "success";

    await db.update(
      DBTables.users,
      values,
      where: '${DBTables.id} = ?',
      whereArgs: [userId],
    );

    return "success";
  }

  // ==========================
  // FAVORITES
  // ==========================

  Future<bool> isFavorite(int userId, int productId) async {
    final db = await database;

    final result = await db.query(
      DBTables.favorites,
      where:
          '${DBTables.favoriteUserId} = ? AND ${DBTables.favoriteProductId} = ?',
      whereArgs: [userId, productId],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  /// Adds the product to favorites if not already there, otherwise
  /// removes it. Returns the new favorited state.
  Future<bool> toggleFavorite(int userId, int productId) async {
    final db = await database;

    final existing = await db.query(
      DBTables.favorites,
      where:
          '${DBTables.favoriteUserId} = ? AND ${DBTables.favoriteProductId} = ?',
      whereArgs: [userId, productId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await db.delete(
        DBTables.favorites,
        where: '${DBTables.id} = ?',
        whereArgs: [existing.first[DBTables.id]],
      );
      return false;
    }

    await db.insert(DBTables.favorites, {
      DBTables.favoriteUserId: userId,
      DBTables.favoriteProductId: productId,
    });
    return true;
  }

  Future<int> removeFavorite(int userId, int productId) async {
    final db = await database;

    return await db.delete(
      DBTables.favorites,
      where:
          '${DBTables.favoriteUserId} = ? AND ${DBTables.favoriteProductId} = ?',
      whereArgs: [userId, productId],
    );
  }

  /// Every product [userId] has favorited, newest-favorited first.
  Future<List<Map<String, dynamic>>> getFavoriteProducts(int userId) async {
    final db = await database;

    return await db.rawQuery(
      '''
      SELECT p.*
      FROM ${DBTables.favorites} f
      INNER JOIN ${DBTables.products} p
        ON p.${DBTables.id} = f.${DBTables.favoriteProductId}
      WHERE f.${DBTables.favoriteUserId} = ?
      ORDER BY f.${DBTables.id} DESC
    ''',
      [userId],
    );
  }

  /// Just the favorited product ids, newest-first — used now that
  /// product data itself lives in Firestore instead of this table, so
  /// the caller fetches full product info from there via the ids
  /// returned here.
  Future<List<int>> getFavoriteProductIds(int userId) async {
    final db = await database;

    final rows = await db.query(
      DBTables.favorites,
      columns: [DBTables.favoriteProductId],
      where: "${DBTables.favoriteUserId} = ?",
      whereArgs: [userId],
      orderBy: "${DBTables.id} DESC",
    );

    return rows.map((r) => r[DBTables.favoriteProductId] as int).toList();
  }

  // ==========================
  // DELIVERY ADDRESSES
  // ==========================

  Future<List<Map<String, dynamic>>> getAddressesForUser(int userId) async {
    final db = await database;

    return await db.query(
      DBTables.deliveryAddresses,
      where: '${DBTables.addressUserId} = ?',
      whereArgs: [userId],
      orderBy: '${DBTables.addressIsDefault} DESC, ${DBTables.id} DESC',
    );
  }

  /// Inserts a new address. If it's the user's first address, or
  /// [isDefault] is true, it becomes the default (clearing the flag
  /// on any other address for this user).
  Future<int> insertAddress(Map<String, dynamic> address) async {
    final db = await database;

    final userId = address[DBTables.addressUserId] as int;
    final existingCount = await db.query(
      DBTables.deliveryAddresses,
      where: '${DBTables.addressUserId} = ?',
      whereArgs: [userId],
    );

    final shouldBeDefault =
        existingCount.isEmpty || (address[DBTables.addressIsDefault] == 1);

    if (shouldBeDefault) {
      await db.update(
        DBTables.deliveryAddresses,
        {DBTables.addressIsDefault: 0},
        where: '${DBTables.addressUserId} = ?',
        whereArgs: [userId],
      );
    }

    address[DBTables.addressIsDefault] = shouldBeDefault ? 1 : 0;

    return await db.insert(DBTables.deliveryAddresses, address);
  }

  Future<int> updateAddress(int id, Map<String, dynamic> address) async {
    final db = await database;

    if (address[DBTables.addressIsDefault] == 1) {
      final userId = address[DBTables.addressUserId] as int;
      await db.update(
        DBTables.deliveryAddresses,
        {DBTables.addressIsDefault: 0},
        where: '${DBTables.addressUserId} = ?',
        whereArgs: [userId],
      );
    }

    return await db.update(
      DBTables.deliveryAddresses,
      address,
      where: '${DBTables.id} = ?',
      whereArgs: [id],
    );
  }

  /// Makes [id] the default address for [userId], clearing the flag
  /// on every other address that user has.
  Future<void> setDefaultAddress(int userId, int id) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.update(
        DBTables.deliveryAddresses,
        {DBTables.addressIsDefault: 0},
        where: '${DBTables.addressUserId} = ?',
        whereArgs: [userId],
      );
      await txn.update(
        DBTables.deliveryAddresses,
        {DBTables.addressIsDefault: 1},
        where: '${DBTables.id} = ?',
        whereArgs: [id],
      );
    });
  }

  /// Deletes an address. If it was the default and other addresses
  /// remain, promotes the most recently added one to default.
  Future<void> deleteAddress(int userId, int id) async {
    final db = await database;

    await db.delete(
      DBTables.deliveryAddresses,
      where: '${DBTables.id} = ?',
      whereArgs: [id],
    );

    final remaining = await getAddressesForUser(userId);
    final hasDefault = remaining.any(
      (row) => (row[DBTables.addressIsDefault] as int) == 1,
    );

    if (!hasDefault && remaining.isNotEmpty) {
      await db.update(
        DBTables.deliveryAddresses,
        {DBTables.addressIsDefault: 1},
        where: '${DBTables.id} = ?',
        whereArgs: [remaining.first[DBTables.id]],
      );
    }
  }

  // ==========================
  // USER SETTINGS
  // ==========================

  /// Returns this user's notification settings, creating a
  /// default (everything on) row the first time it's requested.
  Future<Map<String, dynamic>> getUserSettings(int userId) async {
    final db = await database;

    final result = await db.query(
      DBTables.userSettings,
      where: '${DBTables.settingsUserId} = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (result.isNotEmpty) return result.first;

    final defaults = {
      DBTables.settingsUserId: userId,
      DBTables.settingsPushEnabled: 1,
      DBTables.settingsEmailEnabled: 1,
      DBTables.settingsOrderUpdates: 1,
      DBTables.settingsPromoOffers: 1,
    };

    await db.insert(DBTables.userSettings, defaults);
    return defaults;
  }

  Future<void> updateUserSettings(
    int userId,
    Map<String, dynamic> values,
  ) async {
    final db = await database;

    // Make sure a row exists before updating.
    await getUserSettings(userId);

    await db.update(
      DBTables.userSettings,
      values,
      where: '${DBTables.settingsUserId} = ?',
      whereArgs: [userId],
    );
  }

  Future<void> deleteDatabaseFile() async {
    final databasePath = await getDatabasesPath();

    final path = join(databasePath, DBTables.databaseName);

    await deleteDatabase(path);

    _database = null;
    _databaseFuture = null;
  }

  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
    _database = null;
    _databaseFuture = null;
  }

  // ==========================
  // NOTIFICATIONS
  // ==========================

  Future<int> insertNotification(Map<String, dynamic> notification) async {
    final db = await database;

    return await db.insert(DBTables.notifications, notification);
  }

  Future<List<Map<String, dynamic>>> getNotificationsForUser(int userId) async {
    final db = await database;

    return await db.query(
      DBTables.notifications,
      where: '${DBTables.notifUserId} = ?',
      whereArgs: [userId],
      orderBy: '${DBTables.notifDate} DESC',
    );
  }

  Future<int> getUnreadNotificationCount(int userId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${DBTables.notifications}
      WHERE ${DBTables.notifUserId} = ? AND ${DBTables.isRead} = 0
      ''',
      [userId],
    );

    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> markNotificationRead(int id) async {
    final db = await database;

    return await db.update(
      DBTables.notifications,
      {DBTables.isRead: 1},
      where: '${DBTables.id} = ?',
      whereArgs: [id],
    );
  }

  Future<int> markAllNotificationsRead(int userId) async {
    final db = await database;

    return await db.update(
      DBTables.notifications,
      {DBTables.isRead: 1},
      where: '${DBTables.notifUserId} = ? AND ${DBTables.isRead} = 0',
      whereArgs: [userId],
    );
  }

  // ==========================
  // MESSAGES
  // ==========================

  Future<int> sendMessage(Map<String, dynamic> message) async {
    final db = await database;

    return await db.insert(DBTables.messages, message);
  }

  /// All messages either sent or received by [userId], oldest first.
  /// Conversation grouping/unread-counting is done in Dart (see
  /// MessageRepository) rather than a fragile aggregate SQL query.
  Future<List<Map<String, dynamic>>> getMessagesForUser(int userId) async {
    final db = await database;

    return await db.query(
      DBTables.messages,
      where: '${DBTables.senderId} = ? OR ${DBTables.receiverId} = ?',
      whereArgs: [userId, userId],
      orderBy: '${DBTables.messageDate} ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getConversation(
    int userA,
    int userB,
  ) async {
    final db = await database;

    return await db.query(
      DBTables.messages,
      where:
          '(${DBTables.senderId} = ? AND ${DBTables.receiverId} = ?) OR '
          '(${DBTables.senderId} = ? AND ${DBTables.receiverId} = ?)',
      whereArgs: [userA, userB, userB, userA],
      orderBy: '${DBTables.messageDate} ASC',
    );
  }

  Future<int> markConversationRead({
    required int currentUserId,
    required int otherUserId,
  }) async {
    final db = await database;

    return await db.update(
      DBTables.messages,
      {DBTables.isRead: 1},
      where:
          '${DBTables.receiverId} = ? AND ${DBTables.senderId} = ? AND ${DBTables.isRead} = 0',
      whereArgs: [currentUserId, otherUserId],
    );
  }
}
