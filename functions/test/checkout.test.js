const assert = require("node:assert/strict");

const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

const checkout = require("../src/checkout");
const reviews = require("../src/reviews");
const resources = require("../src/resources");

const projectId = process.env.GCLOUD_PROJECT || "craft-of-love-rules-test";
const app = initializeApp({projectId}, "checkout-tests");
const db = getFirestore(app);

const customer = {uid: "customer-uid", id: 101, accountType: "Customer"};
const otherCustomer = {uid: "other-customer-uid", id: 102, accountType: "Customer"};
const sellerOne = {uid: "seller-one-uid", id: 201, accountType: "Seller"};
const sellerTwo = {uid: "seller-two-uid", id: 202, accountType: "Seller"};

function profile(user, extra = {}) {
  return {
    id: user.id,
    firebaseUid: user.uid,
    accountType: user.accountType,
    firstName: user.accountType === "Seller" ? "Seller" : "Customer",
    lastName: String(user.id),
    email: `${user.uid}@example.test`,
    ...extra,
  };
}

function product(id, sellerId, price, stock) {
  return {
    id,
    sellerId,
    categoryId: 1,
    productName: `Product ${id}`,
    description: "Handmade",
    image: "",
    price,
    stock,
    totalSold: 0,
    pricingMode: "single",
    options: [],
  };
}

function request(items, voucherIds = {}) {
  return {
    items,
    voucherIds,
    paymentMethod: "Cash on Delivery",
    deliveryAddress: {
      fullName: "Test Customer",
      phone: "09123456789",
      label: "Home",
      line1: "123 Test Street",
      city: "Manila",
      province: "Metro Manila",
      postalCode: "1000",
    },
  };
}

function productRequest(overrides = {}) {
  return {
    product: {
      id: 999999,
      sellerId: 999999,
      categoryId: 1,
      categoryGroup: "Home",
      categoryName: "Decor",
      productName: "Server-created product",
      description: "Handmade",
      price: 350,
      stock: 4,
      image: "",
      rating: 5,
      reviewCount: 99,
      totalSold: 99,
      isFlashSale: false,
      discountPercent: 0,
      freeShipping: false,
      codAvailable: true,
      makingProcess: null,
      media: [],
      tags: ["handmade"],
      pricingMode: "single",
      options: [],
      ...overrides,
    },
  };
}

async function clearFirestore() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  assert.ok(host, "FIRESTORE_EMULATOR_HOST must be set");
  const response = await fetch(
    `http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    {method: "DELETE"},
  );
  assert.equal(response.ok, true, await response.text());
}

async function seedBase() {
  const batch = db.batch();
  for (const user of [customer, otherCustomer, sellerOne, sellerTwo]) {
    batch.set(
      db.collection("users").doc(user.uid),
      profile(user, user.accountType === "Seller" ? {shopName: `Shop ${user.id}`} : {}),
    );
  }
  batch.set(db.collection("products").doc("301"), product(301, sellerOne.id, 500, 3));
  batch.set(db.collection("products").doc("302"), product(302, sellerTwo.id, 200, 2));
  await batch.commit();
}

async function seedVoucher(id = "campaign-1_101") {
  await db.collection("customerVouchers").doc(id).set({
    campaignId: "campaign-1",
    customerId: customer.id,
    sellerId: sellerOne.id,
    type: "percentage",
    value: 10,
    minimum: 500,
    maximum: 100,
    claimedAt: Timestamp.now(),
    expiresAt: Timestamp.fromMillis(Date.now() + 7 * 86400000),
    orderId: null,
  });
  return id;
}

async function seedCampaign(quantity = 10) {
  await db.collection("followerCampaigns").doc(String(sellerOne.id)).set({
    sellerId: sellerOne.id,
    campaignId: "follow-campaign",
    status: "active",
    type: "percentage",
    value: 10,
    minimum: 500,
    maximum: 100,
    quantity,
    claimed: 0,
    validDays: 7,
    startsAt: Timestamp.fromMillis(Date.now() - 60000),
    expiresAt: Timestamp.fromMillis(Date.now() + 30 * 86400000),
  });
}

async function seedDeliveredOrder(user, id, productId = 301, itemStatus = "Delivered") {
  await db.collection("orders").doc(String(id)).set({
    id,
    customerId: user.id,
    sellerIds: [sellerOne.id],
    productIds: [productId],
    items: [{
      productId,
      sellerId: sellerOne.id,
      quantity: 1,
      itemPrice: 500,
      status: itemStatus,
    }],
    status: itemStatus,
  });
}

describe("trusted checkout operations", () => {
  beforeEach(async () => {
    await clearFirestore();
    await seedBase();
  });

  after(async () => {
    await clearFirestore();
    await deleteApp(app);
  });

  it("uses authoritative prices and atomically decrements stock", async () => {
    const result = await checkout.placeOrder(
      db,
      customer.uid,
      request([{productId: 301, quantity: 1, itemPrice: 1}]),
    );

    assert.equal(result.subtotal, 500);
    assert.equal(result.total, 500);
    const order = (await db.collection("orders").doc(String(result.orderId)).get()).data();
    assert.equal(order.items[0].itemPrice, 500);
    assert.equal(order.customerId, customer.id);
    const storedProduct = (await db.collection("products").doc("301").get()).data();
    assert.equal(storedProduct.stock, 2);
    assert.equal(storedProduct.totalSold, 1);
  });

  it("honors recipient notification preferences for order events", async () => {
    await db.collection("users").doc(sellerOne.uid).update({
      notificationPreferences: {
        pushEnabled: true,
        emailEnabled: false,
        orderUpdates: false,
        promoOffers: true,
      },
    });
    await db.collection("users").doc(customer.uid).update({
      notificationPreferences: {
        pushEnabled: false,
        emailEnabled: false,
        orderUpdates: true,
        promoOffers: true,
      },
    });

    const placed = await checkout.placeOrder(db, customer.uid, request([
      {productId: 301, quantity: 1},
    ]));
    let notifications = await db.collection("notifications").get();
    assert.equal(notifications.empty, true);

    await checkout.updateSellerOrder(db, sellerOne.uid, {
      orderId: placed.orderId,
      status: "Preparing",
    });
    notifications = await db.collection("notifications").get();
    assert.equal(notifications.empty, true);
  });

  it("rejects insufficient stock without creating a partial order", async () => {
    await assert.rejects(
      checkout.placeOrder(db, customer.uid, request([{productId: 301, quantity: 4}])),
      (error) => error.code === "failed-precondition",
    );
    const productAfter = (await db.collection("products").doc("301").get()).data();
    assert.equal(productAfter.stock, 3);
    assert.equal((await db.collection("orders").get()).size, 0);
  });

  it("requires a supported payment method and complete delivery address", async () => {
    await assert.rejects(
      checkout.placeOrder(db, customer.uid, {
        ...request([{productId: 301, quantity: 1}]),
        paymentMethod: "Unverified Wallet",
      }),
      (error) => error.code === "invalid-argument",
    );
    await assert.rejects(
      checkout.placeOrder(db, customer.uid, {
        ...request([{productId: 301, quantity: 1}]),
        deliveryAddress: {fullName: "Test Customer"},
      }),
      (error) => error.code === "invalid-argument",
    );
  });

  it("redeems each voucher once and rejects reuse", async () => {
    const voucherId = await seedVoucher();
    const first = await checkout.placeOrder(
      db,
      customer.uid,
      request([{productId: 301, quantity: 1}], {[sellerOne.id]: voucherId}),
    );
    assert.equal(first.discount, 50);
    assert.equal(first.total, 450);
    const voucher = (await db.collection("customerVouchers").doc(voucherId).get()).data();
    assert.equal(voucher.orderId, first.orderId);

    await assert.rejects(
      checkout.placeOrder(
        db,
        customer.uid,
        request([{productId: 301, quantity: 1}], {[sellerOne.id]: voucherId}),
      ),
      (error) => error.code === "failed-precondition",
    );
  });

  it("blocks another customer from cancelling an order", async () => {
    const order = await checkout.placeOrder(
      db,
      customer.uid,
      request([{productId: 301, quantity: 1}]),
    );
    await assert.rejects(
      checkout.cancelOrderItem(db, otherCustomer.uid, {
        orderId: order.orderId,
        itemIndex: 0,
      }),
      (error) => error.code === "permission-denied",
    );
  });

  it("restores inventory and the voucher after full cancellation", async () => {
    const voucherId = await seedVoucher();
    const order = await checkout.placeOrder(
      db,
      customer.uid,
      request([{productId: 301, quantity: 1}], {[sellerOne.id]: voucherId}),
    );
    await checkout.cancelOrderItem(db, customer.uid, {
      orderId: order.orderId,
      itemIndex: 0,
    });

    const storedOrder = (await db.collection("orders").doc(String(order.orderId)).get()).data();
    const storedProduct = (await db.collection("products").doc("301").get()).data();
    const voucher = (await db.collection("customerVouchers").doc(voucherId).get()).data();
    assert.equal(storedOrder.status, "Cancelled");
    assert.equal(storedOrder.total, 0);
    assert.equal(storedProduct.stock, 3);
    assert.equal(storedProduct.totalSold, 0);
    assert.equal(voucher.orderId, null);
  });

  it("lets a seller update only that seller's line items", async () => {
    const order = await checkout.placeOrder(
      db,
      customer.uid,
      request([
        {productId: 301, quantity: 1},
        {productId: 302, quantity: 1},
      ]),
    );
    await checkout.updateSellerOrder(db, sellerOne.uid, {
      orderId: order.orderId,
      status: "Preparing",
      currentLocation: "Seller one workshop",
    });
    const stored = (await db.collection("orders").doc(String(order.orderId)).get()).data();
    assert.equal(stored.items.find((item) => item.sellerId === sellerOne.id).status, "Preparing");
    assert.equal(stored.items.find((item) => item.sellerId === sellerTwo.id).status, "Pending");
    assert.equal(stored.sellerFulfillment[String(sellerOne.id)].status, "Preparing");
    assert.equal(stored.sellerFulfillment[String(sellerTwo.id)].status, "Pending");

    await assert.rejects(
      checkout.updateSellerOrder(db, sellerTwo.uid, {
        orderId: order.orderId,
        status: "Delivered",
      }),
      (error) => error.code === "failed-precondition",
    );
  });

  it("issues a first-follow voucher only once across unfollow and refollow", async () => {
    await seedCampaign();
    const first = await checkout.toggleShopFollow(db, customer.uid, {sellerId: sellerOne.id});
    assert.equal(first.following, true);
    assert.ok(first.voucherId);

    const unfollow = await checkout.toggleShopFollow(db, customer.uid, {sellerId: sellerOne.id});
    assert.equal(unfollow.following, false);
    const refollow = await checkout.toggleShopFollow(db, customer.uid, {sellerId: sellerOne.id});
    assert.equal(refollow.following, true);
    assert.equal(refollow.voucherId, null);

    const campaign = (await db.collection("followerCampaigns").doc(String(sellerOne.id)).get()).data();
    assert.equal(campaign.claimed, 1);
    assert.equal((await db.collection("customerVouchers").get()).size, 1);
  });

  it("enforces campaign quantity under concurrent follows", async () => {
    await seedCampaign(1);
    const results = await Promise.all([
      checkout.toggleShopFollow(db, customer.uid, {sellerId: sellerOne.id}),
      checkout.toggleShopFollow(db, otherCustomer.uid, {sellerId: sellerOne.id}),
    ]);
    assert.equal(results.filter((result) => result.voucherId != null).length, 1);
    assert.equal((await db.collection("customerVouchers").get()).size, 1);
    const campaign = (await db.collection("followerCampaigns").doc(String(sellerOne.id)).get()).data();
    assert.equal(campaign.claimed, 1);
  });

  it("allows only a customer with a delivered line item to review", async () => {
    await assert.rejects(
      reviews.submitReview(db, customer.uid, {productId: 301, rating: 5}),
      (error) => error.code === "failed-precondition",
    );
    await seedDeliveredOrder(customer, 5001, 301, "Pending");
    await assert.rejects(
      reviews.submitReview(db, customer.uid, {productId: 301, rating: 5}),
      (error) => error.code === "failed-precondition",
    );
    await seedDeliveredOrder(customer, 5001);
    const result = await reviews.submitReview(db, customer.uid, {
      productId: 301,
      rating: 5,
      comment: "Excellent",
    });
    assert.equal(result.rating, 5);
    assert.equal(result.reviewCount, 1);
  });

  it("updates one review per customer without increasing the count", async () => {
    await seedDeliveredOrder(customer, 5002);
    await reviews.submitReview(db, customer.uid, {productId: 301, rating: 5});
    await reviews.submitReview(db, customer.uid, {productId: 301, rating: 3});

    const productAfter = (await db.collection("products").doc("301").get()).data();
    const reviewSnapshot = await db.collection("reviews").get();
    assert.equal(reviewSnapshot.size, 1);
    assert.equal(productAfter.rating, 3);
    assert.equal(productAfter.ratingTotal, 3);
    assert.equal(productAfter.reviewCount, 1);
  });

  it("keeps concurrent review aggregation consistent", async () => {
    await seedDeliveredOrder(customer, 5003);
    await seedDeliveredOrder(otherCustomer, 5004);
    await Promise.all([
      reviews.submitReview(db, customer.uid, {productId: 301, rating: 5}),
      reviews.submitReview(db, otherCustomer.uid, {productId: 301, rating: 4}),
    ]);

    const productAfter = (await db.collection("products").doc("301").get()).data();
    assert.equal(productAfter.rating, 4.5);
    assert.equal(productAfter.ratingTotal, 9);
    assert.equal(productAfter.reviewCount, 2);
  });

  it("allocates unique user IDs and is idempotent per authenticated user", async () => {
    const [first, second] = await Promise.all([
      resources.ensureUserProfile(db, "new-user-a", "a@example.test", "password", {
        firstName: "New",
        lastName: "A",
        accountType: "Customer",
      }),
      resources.ensureUserProfile(db, "new-user-b", "b@example.test", "google.com", {
        firstName: "New",
        lastName: "B",
        accountType: "Seller",
        shopName: "New Shop",
        sellerVerification: {
          sellerType: "student",
          birthDate: "2000-01-01",
          address: "123 Test Street, Test City",
          identityDocumentType: "national_id",
          payoutMethod: "gcash",
          payoutAccountName: "New B",
          organizationName: "Test University",
        },
      }),
    ]);
    assert.notEqual(first.id, second.id);
    assert.ok(first.id > sellerTwo.id);
    assert.ok(second.id > sellerTwo.id);
    assert.equal(second.sellerVerification.status, "under_review");
    assert.equal(second.sellerVerification.listingLimit, 5);

    const privateApplication = (
      await db.collection("sellerVerificationApplications").doc("new-user-b").get()
    ).data();
    assert.equal(privateApplication.address, "123 Test Street, Test City");
    assert.equal(privateApplication.email, "b@example.test");

    const repeated = await resources.ensureUserProfile(
      db,
      "new-user-a",
      "changed@example.test",
      "password",
      {firstName: "Changed", accountType: "Seller"},
    );
    assert.equal(repeated.id, first.id);
    assert.equal(repeated.accountType, "Customer");
    assert.equal(repeated.email, "a@example.test");
  });

  it("creates products with server-owned IDs, seller identity, and aggregates", async () => {
    const [first, second] = await Promise.all([
      resources.createProduct(db, sellerOne.uid, productRequest()),
      resources.createProduct(db, sellerOne.uid, productRequest({productName: "Second"})),
    ]);
    assert.notEqual(first.productId, second.productId);
    const stored = (await db.collection("products").doc(String(first.productId)).get()).data();
    assert.equal(stored.id, first.productId);
    assert.equal(stored.sellerId, sellerOne.id);
    assert.equal(stored.rating, 0);
    assert.equal(stored.ratingTotal, 0);
    assert.equal(stored.reviewCount, 0);
    assert.equal(stored.totalSold, 0);
  });

  it("rejects product creation by customers", async () => {
    await assert.rejects(
      resources.createProduct(db, customer.uid, productRequest()),
      (error) => error.code === "permission-denied",
    );
  });

  it("enforces the starter listing limit while seller verification is reviewed", async () => {
    await db.collection("users").doc(sellerOne.uid).update({
      sellerVerification: {
        sellerType: "student",
        status: "under_review",
        level: "registered",
        listingLimit: 5,
      },
    });

    for (let index = 0; index < 5; index++) {
      await resources.createProduct(
        db,
        sellerOne.uid,
        productRequest({productName: `Starter listing ${index + 1}`}),
      );
    }

    await assert.rejects(
      resources.createProduct(
        db,
        sellerOne.uid,
        productRequest({productName: "Listing six"}),
      ),
      (error) => error.code === "failed-precondition",
    );
  });
});
