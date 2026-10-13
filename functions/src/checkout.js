const {FieldValue, Timestamp} = require("firebase-admin/firestore");

const PAYMENT_METHODS = new Set([
  "Cash on Delivery",
  "GCash",
  "Maya",
  "Bank Account",
]);

const ORDER_STATUSES = [
  "Pending",
  "Preparing",
  "Shipped",
  "Out for Delivery",
  "Delivered",
  "Cancelled",
];

const STATUS_TRANSITIONS = {
  Pending: new Set(["Preparing", "Cancelled"]),
  Preparing: new Set(["Shipped", "Cancelled"]),
  Shipped: new Set(["Out for Delivery"]),
  "Out for Delivery": new Set(["Delivered"]),
  Delivered: new Set(),
  Cancelled: new Set(),
};

class CheckoutError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "CheckoutError";
    this.code = code;
  }
}

function fail(code, message) {
  throw new CheckoutError(code, message);
}

function objectValue(value, message = "Invalid request.") {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("invalid-argument", message);
  }
  return value;
}

function integer(value, message) {
  if (!Number.isSafeInteger(value)) fail("invalid-argument", message);
  return value;
}

function money(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function requiredText(value, label, maxLength) {
  const result = typeof value === "string" ? value.trim() : "";
  if (!result || result.length > maxLength) {
    fail("invalid-argument", `${label} is required.`);
  }
  return result;
}

function optionalText(value, maxLength) {
  if (value == null) return "";
  if (typeof value !== "string" || value.trim().length > maxLength) {
    fail("invalid-argument", "Invalid text value.");
  }
  return value.trim();
}

function cleanAddress(raw) {
  const address = objectValue(raw, "A delivery address is required.");
  return {
    addressId: Number.isSafeInteger(address.addressId) ? address.addressId : null,
    fullName: requiredText(address.fullName, "Recipient name", 120),
    phone: requiredText(address.phone, "Phone number", 30),
    label: optionalText(address.label, 40) || "Home",
    line1: requiredText(address.line1, "Street address", 200),
    line2: optionalText(address.line2, 200) || null,
    city: requiredText(address.city, "City", 100),
    province: requiredText(address.province, "Province", 100),
    postalCode: optionalText(address.postalCode, 20) || null,
  };
}

function normalizeItems(rawItems) {
  if (!Array.isArray(rawItems) || rawItems.length === 0 || rawItems.length > 30) {
    fail("invalid-argument", "Choose between 1 and 30 products.");
  }
  const grouped = new Map();
  for (const raw of rawItems) {
    const item = objectValue(raw);
    const productId = integer(item.productId, "Invalid product.");
    const quantity = integer(item.quantity, "Invalid quantity.");
    if (productId <= 0 || quantity <= 0 || quantity > 99) {
      fail("invalid-argument", "Invalid product quantity.");
    }
    const optionId = item.optionId == null ? null : optionalText(item.optionId, 120);
    const key = `${productId}:${optionId || ""}`;
    const existing = grouped.get(key);
    if (existing) {
      existing.quantity += quantity;
      if (existing.quantity > 99) fail("invalid-argument", "Invalid product quantity.");
    } else {
      grouped.set(key, {productId, optionId: optionId || null, quantity});
    }
  }
  return [...grouped.values()];
}

function normalizeVoucherIds(raw) {
  if (raw == null) return new Map();
  const vouchers = objectValue(raw, "Invalid vouchers.");
  const result = new Map();
  for (const [sellerKey, voucherId] of Object.entries(vouchers)) {
    const sellerId = Number(sellerKey);
    if (!Number.isSafeInteger(sellerId) || sellerId <= 0) {
      fail("invalid-argument", "Invalid voucher seller.");
    }
    result.set(sellerId, requiredText(voucherId, "Voucher", 200));
  }
  return result;
}

function findOption(product, optionId) {
  const options = Array.isArray(product.options) ? product.options : [];
  const usesOptions = product.pricingMode === "per_image" && options.length > 0;
  if (!usesOptions) {
    if (optionId) fail("failed-precondition", "This product option is no longer available.");
    return null;
  }
  const option = options.find((entry) => entry && entry.id === optionId);
  if (!option) fail("failed-precondition", "Choose an available product option.");
  return option;
}

function timestampMillis(value) {
  if (value instanceof Timestamp) return value.toMillis();
  if (value && typeof value.toMillis === "function") return value.toMillis();
  return Number.NaN;
}

function calculateVoucherDiscount(voucher, subtotal, nowMillis, enforceExpiry) {
  if (subtotal <= 0 || voucher.orderId != null) return 0;
  if (enforceExpiry && timestampMillis(voucher.expiresAt) <= nowMillis) return 0;
  const minimum = Number(voucher.minimum || 0);
  const value = Number(voucher.value);
  if (!Number.isFinite(minimum) || !Number.isFinite(value) || subtotal < minimum) return 0;
  let discount;
  if (voucher.type === "percentage") {
    if (value <= 0 || value > 100) return 0;
    discount = subtotal * value / 100;
    if (voucher.maximum != null) discount = Math.min(discount, Number(voucher.maximum));
  } else if (voucher.type === "fixed") {
    if (value <= 0) return 0;
    discount = value;
  } else {
    return 0;
  }
  return money(Math.min(discount, subtotal));
}

function overallStatus(items) {
  const statuses = items.map((item) => item.status || "Pending");
  const active = statuses.filter((status) => status !== "Cancelled");
  if (active.length === 0) return "Cancelled";
  if (active.every((status) => status === "Delivered")) return "Delivered";
  for (const status of ["Out for Delivery", "Shipped", "Preparing"]) {
    if (active.includes(status)) return status;
  }
  return "Pending";
}

function sellerSubtotal(items, sellerId) {
  return money(items
    .filter((item) => item.sellerId === sellerId && item.status !== "Cancelled")
    .reduce((sum, item) => sum + Number(item.itemPrice) * Number(item.quantity), 0));
}

function initialTracking(nowIso) {
  return {
    courier: "",
    trackingNumber: "",
    estimatedDeliveryDate: "",
    currentLocation: "Order placed",
    lastUpdated: nowIso,
    history: [{status: "Pending", location: "Order placed", date: nowIso}],
  };
}

function notificationsAllowed(profile, category) {
  const preferences = profile?.notificationPreferences || {};
  if (preferences.pushEnabled === false) return false;
  if (category === "order" && preferences.orderUpdates === false) return false;
  if (category === "promo" && preferences.promoOffers === false) return false;
  return true;
}

async function authenticatedProfile(transaction, db, uid, accountType) {
  const snapshot = await transaction.get(db.collection("users").doc(uid));
  const profile = snapshot.data();
  if (!profile || !Number.isSafeInteger(profile.id)) {
    fail("failed-precondition", "Complete your account profile first.");
  }
  if (accountType && profile.accountType !== accountType) {
    fail("permission-denied", `A ${accountType.toLowerCase()} account is required.`);
  }
  return profile;
}

function productUpdate(product, purchasedItems, direction) {
  const quantity = purchasedItems.reduce((sum, item) => sum + item.quantity, 0);
  const options = Array.isArray(product.options)
    ? product.options.map((option) => ({...option}))
    : [];
  if (product.pricingMode === "per_image" && options.length > 0) {
    for (const item of purchasedItems) {
      const option = options.find((entry) => entry.id === item.optionId);
      if (!option) fail("failed-precondition", "A product option is unavailable.");
      const nextStock = Number(option.stock || 0) + direction * item.quantity;
      if (nextStock < 0) fail("failed-precondition", `${product.productName || "Product"} is out of stock.`);
      option.stock = nextStock;
    }
    return {
      options,
      stock: options.reduce((sum, option) => sum + Number(option.stock || 0), 0),
      totalSold: FieldValue.increment(-direction * quantity),
    };
  }
  const stock = Number(product.stock || 0) + direction * quantity;
  if (stock < 0) fail("failed-precondition", `${product.productName || "Product"} is out of stock.`);
  return {stock, totalSold: FieldValue.increment(-direction * quantity)};
}

async function placeOrder(db, uid, rawData) {
  const data = objectValue(rawData);
  const requestedItems = normalizeItems(data.items);
  const voucherIds = normalizeVoucherIds(data.voucherIds);
  const paymentMethod = requiredText(data.paymentMethod, "Payment method", 60);
  if (!PAYMENT_METHODS.has(paymentMethod)) fail("invalid-argument", "Unsupported payment method.");
  const deliveryAddress = cleanAddress(data.deliveryAddress);
  const now = Timestamp.now();
  const nowMillis = now.toMillis();
  const nowIso = now.toDate().toISOString();

  return db.runTransaction(async (transaction) => {
    const customer = await authenticatedProfile(transaction, db, uid, "Customer");
    const productRecords = new Map();
    for (const requested of requestedItems) {
      if (!productRecords.has(requested.productId)) {
        const ref = db.collection("products").doc(String(requested.productId));
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists) fail("failed-precondition", "A selected product is unavailable.");
        productRecords.set(requested.productId, {ref, data: snapshot.data()});
      }
    }

    const sellerIds = [...new Set([...productRecords.values()].map((record) => record.data.sellerId))];
    if (sellerIds.some((sellerId) => !Number.isSafeInteger(sellerId))) {
      fail("failed-precondition", "A product has an invalid seller.");
    }
    const sellerProfiles = new Map();
    for (const sellerId of sellerIds) {
      const query = db.collection("users").where("id", "==", sellerId).limit(1);
      const snapshot = await transaction.get(query);
      const seller = snapshot.docs[0]?.data();
      if (!seller || seller.accountType !== "Seller") {
        fail("failed-precondition", "A seller account is unavailable.");
      }
      sellerProfiles.set(sellerId, seller);
    }

    const items = [];
    for (const requested of requestedItems) {
      const product = productRecords.get(requested.productId).data;
      const option = findOption(product, requested.optionId);
      const stock = Number(option ? option.stock : product.stock || 0);
      if (!Number.isInteger(stock) || stock < requested.quantity) {
        fail("failed-precondition", `${product.productName || "Product"} does not have enough stock.`);
      }
      const price = Number(option ? option.price : product.price);
      if (!Number.isFinite(price) || price < 0) fail("failed-precondition", "A product has an invalid price.");
      const seller = sellerProfiles.get(product.sellerId);
      items.push({
        productId: requested.productId,
        productName: product.productName || "Product",
        productImage: option?.image || product.image || "",
        optionId: option?.id || null,
        optionName: option?.name || null,
        optionImage: option?.image || product.image || "",
        sellerId: product.sellerId,
        sellerFirstName: seller.firstName || "",
        sellerLastName: seller.lastName || "",
        quantity: requested.quantity,
        itemPrice: money(price),
        status: "Pending",
      });
    }

    const subtotals = new Map(sellerIds.map((sellerId) => [sellerId, sellerSubtotal(items, sellerId)]));
    const voucherSnapshots = new Map();
    for (const [sellerId, voucherId] of voucherIds) {
      if (!subtotals.has(sellerId)) fail("failed-precondition", "Voucher does not match this order.");
      const ref = db.collection("customerVouchers").doc(voucherId);
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) fail("failed-precondition", "Voucher is unavailable.");
      voucherSnapshots.set(sellerId, {ref, id: voucherId, data: snapshot.data()});
    }

    const appliedVouchers = [];
    const discounts = new Map();
    for (const [sellerId, voucher] of voucherSnapshots) {
      if (voucher.data.customerId !== customer.id || voucher.data.sellerId !== sellerId) {
        fail("permission-denied", "Voucher belongs to another account or seller.");
      }
      const discount = calculateVoucherDiscount(voucher.data, subtotals.get(sellerId), nowMillis, true);
      if (discount <= 0) fail("failed-precondition", "Voucher is expired, used, or not eligible.");
      discounts.set(sellerId, discount);
      appliedVouchers.push({voucherId: voucher.id, sellerId, discount});
    }

    const counterRef = db.collection("counters").doc("orders");
    const counterSnapshot = await transaction.get(counterRef);
    const previousId = Number(counterSnapshot.data()?.lastId || 0);
    const orderId = Math.max(Number.isSafeInteger(previousId) ? previousId + 1 : 1, Date.now());
    const orderRef = db.collection("orders").doc(String(orderId));
    const subtotal = money([...subtotals.values()].reduce((sum, value) => sum + value, 0));
    const discount = money([...discounts.values()].reduce((sum, value) => sum + value, 0));
    const sellerFulfillment = {};
    for (const sellerId of sellerIds) {
      const sellerDiscount = discounts.get(sellerId) || 0;
      sellerFulfillment[String(sellerId)] = {
        status: "Pending",
        subtotal: subtotals.get(sellerId),
        discount: sellerDiscount,
        total: money(subtotals.get(sellerId) - sellerDiscount),
        tracking: initialTracking(nowIso),
      };
    }

    for (const [productId, record] of productRecords) {
      transaction.update(
        record.ref,
        productUpdate(record.data, items.filter((item) => item.productId === productId), -1),
      );
    }
    transaction.set(counterRef, {lastId: orderId}, {merge: true});
    transaction.set(orderRef, {
      id: orderId,
      customerId: customer.id,
      customerFirstName: customer.firstName || "",
      customerLastName: customer.lastName || "",
      sellerIds,
      productIds: items.map((item) => item.productId),
      items,
      subtotal,
      discount,
      total: money(subtotal - discount),
      vouchers: appliedVouchers,
      hadVouchers: appliedVouchers.length > 0,
      status: "Pending",
      paymentMethod,
      paymentStatus: paymentMethod === "Cash on Delivery"
        ? "Pay on delivery"
        : "Awaiting payment confirmation",
      deliveryAddress,
      orderDate: nowIso,
      createdAt: now,
      sellerFulfillment,
      tracking: initialTracking(nowIso),
    });
    for (const [sellerId, voucher] of voucherSnapshots) {
      transaction.update(voucher.ref, {
        orderId,
        redeemedAt: now,
        revenue: money(subtotals.get(sellerId) - discounts.get(sellerId)),
      });
    }
    for (const sellerId of sellerIds) {
      const seller = sellerProfiles.get(sellerId);
      if (!notificationsAllowed(seller, "order")) continue;
      const notificationRef = db.collection("notifications").doc();
      transaction.set(notificationRef, {
        userId: sellerId,
        createdById: customer.id,
        title: "New order received",
        body: `Order #${orderId} contains products from your shop.`,
        type: "order",
        relatedId: orderId,
        isRead: false,
        createdDate: nowIso,
        createdAt: now,
      });
    }
    return {orderId, subtotal, discount, total: money(subtotal - discount)};
  });
}

function recalculateOrder(items, vouchers, voucherDataById, nowMillis) {
  const sellerIds = [...new Set(items.map((item) => item.sellerId))];
  const subtotals = new Map(sellerIds.map((sellerId) => [sellerId, sellerSubtotal(items, sellerId)]));
  const keptVouchers = [];
  const voucherChanges = [];
  const discounts = new Map();
  for (const applied of vouchers) {
    const voucher = voucherDataById.get(applied.voucherId);
    if (!voucher) continue;
    const subtotal = subtotals.get(applied.sellerId) || 0;
    if (subtotal <= 0) {
      voucherChanges.push({ref: voucher.ref, data: {orderId: null, redeemedAt: null, revenue: 0}});
      continue;
    }
    const discount = calculateVoucherDiscount({...voucher.data, orderId: null}, subtotal, nowMillis, false);
    discounts.set(applied.sellerId, discount);
    keptVouchers.push({...applied, discount});
    voucherChanges.push({ref: voucher.ref, data: {revenue: money(subtotal - discount)}});
  }
  const subtotal = money([...subtotals.values()].reduce((sum, value) => sum + value, 0));
  const discount = money([...discounts.values()].reduce((sum, value) => sum + value, 0));
  return {subtotals, discounts, vouchers: keptVouchers, voucherChanges, subtotal, discount, total: money(subtotal - discount)};
}

async function loadVoucherData(transaction, db, order) {
  const result = new Map();
  for (const applied of Array.isArray(order.vouchers) ? order.vouchers : []) {
    const ref = db.collection("customerVouchers").doc(applied.voucherId);
    const snapshot = await transaction.get(ref);
    if (snapshot.exists) result.set(applied.voucherId, {ref, data: snapshot.data()});
  }
  return result;
}

async function cancelOrderItem(db, uid, rawData) {
  const data = objectValue(rawData);
  const orderId = integer(data.orderId, "Invalid order.");
  const itemIndex = integer(data.itemIndex, "Invalid order item.");
  const now = Timestamp.now();
  const nowIso = now.toDate().toISOString();

  return db.runTransaction(async (transaction) => {
    const customer = await authenticatedProfile(transaction, db, uid, "Customer");
    const orderRef = db.collection("orders").doc(String(orderId));
    const orderSnapshot = await transaction.get(orderRef);
    if (!orderSnapshot.exists) fail("not-found", "Order not found.");
    const order = orderSnapshot.data();
    if (order.customerId !== customer.id) fail("permission-denied", "This order belongs to another customer.");
    const items = Array.isArray(order.items) ? order.items.map((item) => ({...item})) : [];
    if (itemIndex < 0 || itemIndex >= items.length) fail("not-found", "Order item not found.");
    const item = items[itemIndex];
    if ((item.status || order.status) !== "Pending") {
      fail("failed-precondition", "Only pending products can be cancelled.");
    }
    const productRef = db.collection("products").doc(String(item.productId));
    const productSnapshot = await transaction.get(productRef);
    const voucherData = await loadVoucherData(transaction, db, order);
    const sellerQuery = db.collection("users").where("id", "==", item.sellerId).limit(1);
    const sellerSnapshot = await transaction.get(sellerQuery);
    const sellerProfile = sellerSnapshot.docs[0]?.data();

    item.status = "Cancelled";
    item.cancelledAt = nowIso;
    items[itemIndex] = item;
    const totals = recalculateOrder(items, order.vouchers || [], voucherData, now.toMillis());
    const sellerFulfillment = {...(order.sellerFulfillment || {})};
    const sellerKey = String(item.sellerId);
    const sellerRecord = {...(sellerFulfillment[sellerKey] || {})};
    sellerRecord.subtotal = totals.subtotals.get(item.sellerId) || 0;
    sellerRecord.discount = totals.discounts.get(item.sellerId) || 0;
    sellerRecord.total = money(sellerRecord.subtotal - sellerRecord.discount);
    if (items.filter((entry) => entry.sellerId === item.sellerId).every((entry) => entry.status === "Cancelled")) {
      sellerRecord.status = "Cancelled";
    }
    sellerFulfillment[sellerKey] = sellerRecord;
    const status = overallStatus(items);
    const tracking = {...(order.tracking || initialTracking(nowIso))};
    tracking.lastUpdated = nowIso;
    tracking.currentLocation = status === "Cancelled" ? "Order cancelled" : tracking.currentLocation;
    tracking.history = [...(tracking.history || []), {status: "Cancelled", location: "", date: nowIso}];

    if (productSnapshot.exists) {
      transaction.update(productRef, productUpdate(productSnapshot.data(), [item], 1));
    }
    for (const change of totals.voucherChanges) transaction.update(change.ref, change.data);
    transaction.update(orderRef, {
      items,
      vouchers: totals.vouchers,
      subtotal: totals.subtotal,
      discount: totals.discount,
      total: totals.total,
      status,
      sellerFulfillment,
      tracking,
      updatedAt: now,
    });
    if (notificationsAllowed(sellerProfile, "order")) {
      transaction.set(db.collection("notifications").doc(), {
        userId: item.sellerId,
        createdById: customer.id,
        title: `Product cancelled from order #${orderId}`,
        body: `The customer cancelled "${item.productName || "a product"}".`,
        type: "order",
        relatedId: orderId,
        isRead: false,
        createdDate: nowIso,
        createdAt: now,
      });
    }
    return {orderId, status, total: totals.total};
  });
}

function cleanTracking(data, previous, status, nowIso) {
  const tracking = {...(previous || initialTracking(nowIso))};
  tracking.courier = optionalText(data.courier, 100);
  tracking.trackingNumber = optionalText(data.trackingNumber, 120);
  tracking.estimatedDeliveryDate = optionalText(data.estimatedDeliveryDate, 60);
  tracking.currentLocation = optionalText(data.currentLocation, 200);
  tracking.lastUpdated = nowIso;
  tracking.history = [
    ...(Array.isArray(tracking.history) ? tracking.history : []),
    {status, location: tracking.currentLocation, date: nowIso},
  ];
  return tracking;
}

async function updateSellerOrder(db, uid, rawData) {
  const data = objectValue(rawData);
  const orderId = integer(data.orderId, "Invalid order.");
  const status = requiredText(data.status, "Status", 40);
  if (!ORDER_STATUSES.includes(status)) fail("invalid-argument", "Invalid order status.");
  const now = Timestamp.now();
  const nowIso = now.toDate().toISOString();

  return db.runTransaction(async (transaction) => {
    const seller = await authenticatedProfile(transaction, db, uid, "Seller");
    const orderRef = db.collection("orders").doc(String(orderId));
    const orderSnapshot = await transaction.get(orderRef);
    if (!orderSnapshot.exists) fail("not-found", "Order not found.");
    const order = orderSnapshot.data();
    if (!Array.isArray(order.sellerIds) || !order.sellerIds.includes(seller.id)) {
      fail("permission-denied", "This order does not contain your products.");
    }
    const items = Array.isArray(order.items) ? order.items.map((item) => ({...item})) : [];
    const sellerItems = items.filter((item) => item.sellerId === seller.id && item.status !== "Cancelled");
    if (sellerItems.length === 0) fail("failed-precondition", "No active products remain for this seller.");
    const previousStatus = sellerItems[0].status || "Pending";
    if (status !== previousStatus && !STATUS_TRANSITIONS[previousStatus]?.has(status)) {
      fail("failed-precondition", `Cannot change ${previousStatus} to ${status}.`);
    }

    const productSnapshots = new Map();
    const voucherData = await loadVoucherData(transaction, db, order);
    const customerQuery = db.collection("users").where("id", "==", order.customerId).limit(1);
    const customerSnapshot = await transaction.get(customerQuery);
    const customerProfile = customerSnapshot.docs[0]?.data();
    if (status === "Cancelled") {
      for (const item of sellerItems) {
        if (!productSnapshots.has(item.productId)) {
          const ref = db.collection("products").doc(String(item.productId));
          const snapshot = await transaction.get(ref);
          productSnapshots.set(item.productId, {ref, data: snapshot.data()});
        }
      }
    }

    for (const item of items) {
      if (item.sellerId === seller.id && item.status !== "Cancelled") {
        item.status = status;
        if (status === "Cancelled") item.cancelledAt = nowIso;
      }
    }
    const totals = recalculateOrder(items, order.vouchers || [], voucherData, now.toMillis());
    const sellerFulfillment = {...(order.sellerFulfillment || {})};
    const key = String(seller.id);
    const previousSellerRecord = sellerFulfillment[key] || {};
    const tracking = cleanTracking(data, previousSellerRecord.tracking, status, nowIso);
    sellerFulfillment[key] = {
      ...previousSellerRecord,
      status,
      subtotal: totals.subtotals.get(seller.id) || 0,
      discount: totals.discounts.get(seller.id) || 0,
      total: money((totals.subtotals.get(seller.id) || 0) - (totals.discounts.get(seller.id) || 0)),
      tracking,
    };

    if (status === "Cancelled") {
      for (const [productId, record] of productSnapshots) {
        if (record.data) {
          transaction.update(
            record.ref,
            productUpdate(record.data, sellerItems.filter((item) => item.productId === productId), 1),
          );
        }
      }
      for (const change of totals.voucherChanges) transaction.update(change.ref, change.data);
    }
    const aggregateStatus = overallStatus(items);
    const aggregateTracking = {...(order.tracking || initialTracking(nowIso))};
    aggregateTracking.lastUpdated = nowIso;
    aggregateTracking.currentLocation = tracking.currentLocation;
    aggregateTracking.history = [
      ...(aggregateTracking.history || []),
      {status, location: tracking.currentLocation, date: nowIso, sellerId: seller.id},
    ];
    transaction.update(orderRef, {
      items,
      vouchers: totals.vouchers,
      subtotal: totals.subtotal,
      discount: totals.discount,
      total: totals.total,
      status: aggregateStatus,
      sellerFulfillment,
      tracking: aggregateTracking,
      updatedAt: now,
    });
    if (notificationsAllowed(customerProfile, "order")) {
      transaction.set(db.collection("notifications").doc(), {
        userId: order.customerId,
        createdById: seller.id,
        title: `Order #${orderId} update`,
        body: `${seller.shopName || "A seller"} marked their products as "${status}".`,
        type: "order_status",
        relatedId: orderId,
        sellerId: seller.id,
        isRead: false,
        createdDate: nowIso,
        createdAt: now,
      });
    }
    return {orderId, status: aggregateStatus, sellerStatus: status};
  });
}

async function toggleShopFollow(db, uid, rawData) {
  const data = objectValue(rawData);
  const sellerId = integer(data.sellerId, "Invalid seller.");
  const now = Timestamp.now();

  return db.runTransaction(async (transaction) => {
    const customer = await authenticatedProfile(transaction, db, uid, "Customer");
    if (customer.id === sellerId) fail("failed-precondition", "You cannot follow your own shop.");

    const sellerQuery = db.collection("users").where("id", "==", sellerId).limit(1);
    const sellerSnapshot = await transaction.get(sellerQuery);
    const seller = sellerSnapshot.docs[0]?.data();
    if (!seller || seller.accountType !== "Seller") fail("not-found", "Shop not found.");

    const followRef = db.collection("shopFollows").doc(`${customer.id}_${sellerId}`);
    const historyRef = db.collection("shopFollowHistory").doc(`${customer.id}_${sellerId}`);
    const campaignRef = db.collection("followerCampaigns").doc(String(sellerId));
    const followSnapshot = await transaction.get(followRef);
    const historySnapshot = await transaction.get(historyRef);
    const campaignSnapshot = await transaction.get(campaignRef);

    if (followSnapshot.exists) {
      transaction.delete(followRef);
      transaction.set(historyRef, {customerId: customer.id, sellerId}, {merge: true});
      return {following: false, voucherId: null};
    }

    const campaign = campaignSnapshot.data();
    let voucherRef = null;
    let voucher = null;
    if (!historySnapshot.exists && campaign && campaign.status === "active") {
      const startsAt = timestampMillis(campaign.startsAt);
      const expiresAt = timestampMillis(campaign.expiresAt);
      const claimed = Number(campaign.claimed || 0);
      const quantity = Number(campaign.quantity || 0);
      const validDays = Number(campaign.validDays || 0);
      const campaignId = typeof campaign.campaignId === "string" ? campaign.campaignId : "";
      if (
        campaign.sellerId === sellerId &&
        campaignId &&
        Number.isInteger(validDays) &&
        validDays > 0 &&
        validDays <= 365 &&
        startsAt <= now.toMillis() &&
        now.toMillis() < expiresAt &&
        claimed < quantity
      ) {
        voucherRef = db.collection("customerVouchers").doc(`${campaignId}_${customer.id}`);
        const existingVoucher = await transaction.get(voucherRef);
        if (!existingVoucher.exists) {
          const durationEnd = now.toMillis() + validDays * 86400000;
          voucher = {
            campaignId,
            customerId: customer.id,
            sellerId,
            sellerName: seller.shopName || `${seller.firstName || ""} ${seller.lastName || ""}`.trim() || "Shop",
            type: campaign.type,
            value: campaign.value,
            minimum: campaign.minimum || 0,
            maximum: campaign.maximum ?? null,
            claimedAt: now,
            expiresAt: Timestamp.fromMillis(Math.min(durationEnd, expiresAt)),
            orderId: null,
            redeemedAt: null,
            revenue: 0,
          };
        }
      }
    }

    transaction.set(followRef, {
      followerId: customer.id,
      sellerId,
      createdAt: now,
    });
    if (!historySnapshot.exists) {
      transaction.set(historyRef, {
        customerId: customer.id,
        sellerId,
        firstFollowedAt: now,
      });
    }
    if (voucher && voucherRef) {
      transaction.set(voucherRef, voucher);
      transaction.update(campaignRef, {claimed: FieldValue.increment(1)});
    }
    return {following: true, voucherId: voucherRef && voucher ? voucherRef.id : null};
  });
}

module.exports = {
  CheckoutError,
  calculateVoucherDiscount,
  cancelOrderItem,
  notificationsAllowed,
  overallStatus,
  placeOrder,
  toggleShopFollow,
  updateSellerOrder,
};
