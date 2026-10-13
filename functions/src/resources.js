const {Timestamp} = require("firebase-admin/firestore");

const {CheckoutError} = require("./checkout");

function fail(code, message) {
  throw new CheckoutError(code, message);
}

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function text(value, label, maximum, required = false) {
  if (value == null && !required) return null;
  if (typeof value !== "string") fail("invalid-argument", `${label} is invalid.`);
  const cleaned = value.trim();
  if (required && !cleaned) fail("invalid-argument", `${label} is required.`);
  if (cleaned.length > maximum) fail("invalid-argument", `${label} is too long.`);
  return cleaned || null;
}

function integer(value, label, minimum = 0, maximum = Number.MAX_SAFE_INTEGER) {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < minimum || number > maximum) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return number;
}

function numberValue(value, label, minimum = 0) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < minimum) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return Math.round(number * 100) / 100;
}

function booleanValue(value, label) {
  if (typeof value !== "boolean") fail("invalid-argument", `${label} is invalid.`);
  return value;
}

function stringList(value, label, maximumItems, maximumLength) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > maximumItems) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value.map((item) => text(item, label, maximumLength, true));
}

function cleanSellerVerification(value, accountType, nowIso) {
  if (accountType !== "Seller") return null;
  const input = objectValue(value);
  const sellerType = text(input.sellerType, "Seller type", 20, true);
  if (!new Set(["student", "individual", "business"]).has(sellerType)) {
    fail("invalid-argument", "Seller type is invalid.");
  }

  const birthDate = text(input.birthDate, "Date of birth", 10, true);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(birthDate)) {
    fail("invalid-argument", "Date of birth is invalid.");
  }
  const birth = new Date(`${birthDate}T00:00:00Z`);
  if (Number.isNaN(birth.getTime())) fail("invalid-argument", "Date of birth is invalid.");
  const today = new Date(nowIso);
  let age = today.getUTCFullYear() - birth.getUTCFullYear();
  const beforeBirthday = today.getUTCMonth() < birth.getUTCMonth() ||
    (today.getUTCMonth() === birth.getUTCMonth() && today.getUTCDate() < birth.getUTCDate());
  if (beforeBirthday) age--;
  if (age < 18 || age > 120) {
    fail("failed-precondition", "Sellers must be at least 18 years old.");
  }

  const identityDocumentType = text(
    input.identityDocumentType,
    "Identity document type",
    30,
    true,
  );
  if (!new Set(["national_id", "passport", "drivers_license", "postal_id"])
    .has(identityDocumentType)) {
    fail("invalid-argument", "Identity document type is invalid.");
  }
  const payoutMethod = text(input.payoutMethod, "Payout method", 20, true);
  if (!new Set(["bank", "gcash", "maya"]).has(payoutMethod)) {
    fail("invalid-argument", "Payout method is invalid.");
  }

  const organizationName = text(input.organizationName, "Organization name", 160);
  const businessRegistrationNumber = text(
    input.businessRegistrationNumber,
    "Business registration number",
    80,
  );
  if (sellerType === "business" && (!organizationName || !businessRegistrationNumber)) {
    fail("invalid-argument", "Business name and registration number are required.");
  }

  return {
    sellerType,
    birthDate,
    address: text(input.address, "Address", 300, true),
    identityDocumentType,
    payoutMethod,
    payoutAccountName: text(input.payoutAccountName, "Payout account name", 160, true),
    organizationName,
    businessRegistrationNumber,
    status: "under_review",
    level: "registered",
    listingLimit: 5,
    submittedAt: nowIso,
  };
}

async function nextNumericId(transaction, db, collectionName, counterName) {
  const counterRef = db.collection("counters").doc(counterName);
  const counterSnapshot = await transaction.get(counterRef);
  const highestQuery = db.collection(collectionName).orderBy("id", "desc").limit(1);
  const highestSnapshot = await transaction.get(highestQuery);
  const counterId = Number(counterSnapshot.data()?.lastId || 0);
  const highestId = Number(highestSnapshot.docs[0]?.data()?.id || 0);
  const next = Math.max(
    Number.isSafeInteger(counterId) ? counterId : 0,
    Number.isSafeInteger(highestId) ? highestId : 0,
  ) + 1;
  transaction.set(counterRef, {lastId: next});
  return next;
}

async function ensureUserProfile(db, uid, authEmail, authProvider, rawData) {
  if (typeof uid !== "string" || !uid) fail("unauthenticated", "Sign in to continue.");
  const input = objectValue(rawData);

  return db.runTransaction(async (transaction) => {
    const profileRef = db.collection("users").doc(uid);
    const profileSnapshot = await transaction.get(profileRef);
    const existing = profileSnapshot.data();
    if (existing && Number.isSafeInteger(existing.id)) return existing;

    const numericId = await nextNumericId(transaction, db, "users", "users");
    if (existing) {
      const repaired = {...existing, id: numericId, firebaseUid: uid};
      transaction.set(profileRef, {id: numericId, firebaseUid: uid}, {merge: true});
      return repaired;
    }

    const email = text(authEmail, "Email", 320, true)?.toLowerCase();
    const accountType = text(input.accountType, "Account type", 20, true);
    if (!new Set(["Customer", "Seller"]).has(accountType)) {
      fail("invalid-argument", "Account type is invalid.");
    }
    const provider = text(authProvider, "Authentication provider", 50) || "unknown";
    const nowIso = Timestamp.now().toDate().toISOString();
    const sellerVerification = cleanSellerVerification(
      input.sellerVerification,
      accountType,
      nowIso,
    );
    const profile = {
      id: numericId,
      firebaseUid: uid,
      firstName: text(input.firstName, "First name", 80, true),
      lastName: text(input.lastName, "Last name", 80) || "",
      email,
      phone: text(input.phone, "Phone number", 40),
      accountType,
      shopName: text(input.shopName, "Shop name", 120),
      coverImage: text(input.coverImage, "Cover image", 2048),
      profileImage: text(input.profileImage, "Profile image", 2048),
      isLive: false,
      ...(sellerVerification ? {
        sellerVerification: {
          sellerType: sellerVerification.sellerType,
          status: sellerVerification.status,
          level: sellerVerification.level,
          listingLimit: sellerVerification.listingLimit,
          submittedAt: sellerVerification.submittedAt,
        },
      } : {}),
      authProvider: provider,
      createdAt: nowIso,
    };
    if (sellerVerification) {
      transaction.create(
        db.collection("sellerVerificationApplications").doc(uid),
        {...sellerVerification, uid, email},
      );
    }
    transaction.create(profileRef, profile);
    return profile;
  });
}

function cleanMedia(value) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 20) fail("invalid-argument", "Product media is invalid.");
  return value.map((raw, index) => {
    const media = objectValue(raw);
    const type = text(media.media_type ?? media.type, "Media type", 10, true);
    if (type !== "image" && type !== "video") fail("invalid-argument", "Media type is invalid.");
    return {
      media_type: type,
      path: text(media.path, "Media path", 2048, true),
      position: integer(media.position ?? index, "Media position", 0, 1000),
    };
  });
}

function cleanOptions(value) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 50) fail("invalid-argument", "Product options are invalid.");
  const ids = new Set();
  return value.map((raw) => {
    const option = objectValue(raw);
    const id = text(option.id, "Option ID", 120, true);
    if (ids.has(id)) fail("invalid-argument", "Product option IDs must be unique.");
    ids.add(id);
    return {
      id,
      name: text(option.name, "Option name", 120, true),
      image: text(option.image, "Option image", 2048) || "",
      price: numberValue(option.price, "Option price"),
      stock: integer(option.stock, "Option stock", 0, 1000000),
      isDefault: booleanValue(option.isDefault ?? false, "Default option"),
    };
  });
}

function cleanMakingProcess(value) {
  if (value == null) return null;
  const process = objectValue(value);
  const steps = Array.isArray(process.steps) ? process.steps : [];
  if (steps.length > 30) fail("invalid-argument", "Making steps are invalid.");
  return {
    enabled: booleanValue(process.enabled ?? false, "Making process"),
    estimatedTime: text(process.estimatedTime, "Estimated time", 120) || "",
    skillLevel: text(process.skillLevel, "Skill level", 80) || "",
    materials: stringList(process.materials, "Materials", 50, 120),
    tools: stringList(process.tools, "Tools", 50, 120),
    steps: steps.map((raw) => {
      const step = objectValue(raw);
      return {
        title: text(step.title, "Step title", 160, true),
        description: text(step.description, "Step description", 2000, true),
      };
    }),
    careInstructions: text(process.careInstructions, "Care instructions", 2000) || "",
    safetyNotes: text(process.safetyNotes, "Safety notes", 2000) || "",
    source: "seller",
  };
}

async function createProduct(db, uid, rawData) {
  const input = objectValue(objectValue(rawData).product);
  const pricingMode = text(input.pricingMode, "Pricing mode", 20, true);
  if (!new Set(["single", "per_image"]).has(pricingMode)) {
    fail("invalid-argument", "Pricing mode is invalid.");
  }
  const options = cleanOptions(input.options);
  if (pricingMode === "per_image" && options.length === 0) {
    fail("invalid-argument", "At least one product option is required.");
  }

  return db.runTransaction(async (transaction) => {
    const profileSnapshot = await transaction.get(db.collection("users").doc(uid));
    const seller = profileSnapshot.data();
    if (!seller || seller.accountType !== "Seller" || !Number.isSafeInteger(seller.id)) {
      fail("permission-denied", "Only sellers can create products.");
    }
    const verification = objectValue(seller.sellerVerification);
    if (new Set(["rejected", "suspended"]).has(verification.status)) {
      fail("permission-denied", "Seller verification is required before adding products.");
    }
    const listingLimit = Number(verification.listingLimit);
    if (verification.status === "under_review" && Number.isSafeInteger(listingLimit)) {
      const listings = await transaction.get(
        db.collection("products").where("sellerId", "==", seller.id).limit(listingLimit),
      );
      if (listings.size >= listingLimit) {
        fail(
          "failed-precondition",
          `Your account can publish up to ${listingLimit} listings while verification is reviewed.`,
        );
      }
    }
    const productId = await nextNumericId(transaction, db, "products", "products");
    const productRef = db.collection("products").doc(String(productId));
    const media = cleanMedia(input.media).map((item) => ({...item, product_id: productId}));
    const product = {
      id: productId,
      sellerId: seller.id,
      categoryId: integer(input.categoryId, "Category", 1),
      categoryGroup: text(input.categoryGroup, "Category group", 120),
      categoryName: text(input.categoryName, "Category name", 120),
      productName: text(input.productName, "Product name", 200, true),
      description: text(input.description, "Description", 5000, true),
      price: numberValue(input.price, "Price"),
      stock: integer(input.stock, "Stock", 0, 1000000),
      image: text(input.image, "Product image", 2048) || "",
      rating: 0,
      ratingTotal: 0,
      reviewCount: 0,
      totalSold: 0,
      craftType: text(input.craftType, "Craft type", 120),
      material: text(input.material, "Material", 120),
      occasion: text(input.occasion, "Occasion", 120),
      isFlashSale: booleanValue(input.isFlashSale ?? false, "Flash sale"),
      discountPercent: integer(input.discountPercent ?? 0, "Discount", 0, 100),
      freeShipping: booleanValue(input.freeShipping ?? false, "Free shipping"),
      codAvailable: booleanValue(input.codAvailable ?? false, "Cash on delivery"),
      makingProcess: cleanMakingProcess(input.makingProcess),
      media,
      tags: stringList(input.tags, "Tags", 40, 80),
      pricingMode,
      options,
      createdAt: Timestamp.now(),
    };
    transaction.create(productRef, product);
    return {productId};
  });
}

module.exports = {
  createProduct,
  ensureUserProfile,
  nextNumericId,
};
