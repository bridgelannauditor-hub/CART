const {Timestamp} = require("firebase-admin/firestore");

const {CheckoutError} = require("./checkout");

function fail(code, message) {
  throw new CheckoutError(code, message);
}

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function positiveInteger(value, message) {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number <= 0) fail("invalid-argument", message);
  return number;
}

function validRating(value) {
  const rating = Number(value);
  if (!Number.isFinite(rating) || rating < 1 || rating > 5) {
    fail("invalid-argument", "Rating must be between 1 and 5.");
  }
  return rating;
}

function cleanComment(value) {
  if (value == null) return null;
  if (typeof value !== "string") fail("invalid-argument", "Review comment is invalid.");
  const comment = value.trim();
  if (comment.length > 1000) fail("invalid-argument", "Review comment is too long.");
  return comment || null;
}

function orderContainsDeliveredProduct(order, productId) {
  const items = Array.isArray(order.items) ? order.items : [];
  return items.some((item) =>
    Number(item.productId) === productId &&
    (item.status === "Delivered" || (!item.status && order.status === "Delivered")),
  );
}

async function submitReview(db, uid, rawData) {
  const data = objectValue(rawData);
  const productId = positiveInteger(data.productId, "Invalid product.");
  const rating = validRating(data.rating);
  const comment = cleanComment(data.comment);
  const now = Timestamp.now();
  const nowIso = now.toDate().toISOString();

  return db.runTransaction(async (transaction) => {
    const profileRef = db.collection("users").doc(uid);
    const profileSnapshot = await transaction.get(profileRef);
    if (!profileSnapshot.exists) fail("failed-precondition", "Complete your profile first.");
    const customer = profileSnapshot.data();
    if (customer.accountType !== "Customer" || !Number.isSafeInteger(customer.id)) {
      fail("permission-denied", "Only customers can review products.");
    }

    const productRef = db.collection("products").doc(String(productId));
    const productSnapshot = await transaction.get(productRef);
    if (!productSnapshot.exists) fail("not-found", "Product not found.");
    const product = productSnapshot.data();

    const reviewRef = db.collection("reviews").doc(`${productId}_${customer.id}`);
    const reviewSnapshot = await transaction.get(reviewRef);

    const eligibleOrders = db.collection("orders")
      .where("customerId", "==", customer.id)
      .where("productIds", "array-contains", productId);
    const orderSnapshot = await transaction.get(eligibleOrders);
    const eligible = orderSnapshot.docs.some((doc) =>
      orderContainsDeliveredProduct(doc.data(), productId),
    );
    if (!eligible) {
      fail("failed-precondition", "You can review this product after it is delivered.");
    }

    const existing = reviewSnapshot.data();
    const count = Math.max(0, Number(product.reviewCount || 0));
    const storedTotal = Number(product.ratingTotal);
    const derivedTotal = Number(product.rating || 0) * count;
    const previousTotal = Number.isFinite(storedTotal) ? storedTotal : derivedTotal;
    const previousRating = existing ? Number(existing.rating || 0) : 0;
    const nextCount = existing ? count : count + 1;
    const nextTotal = previousTotal - previousRating + rating;
    const average = nextCount === 0 ? 0 : nextTotal / nextCount;

    transaction.set(reviewRef, {
      productId,
      customerId: customer.id,
      customerFirstName: customer.firstName || "",
      customerLastName: customer.lastName || "",
      rating,
      comment,
      createdAt: existing?.createdAt || nowIso,
      updatedAt: now,
    });
    transaction.update(productRef, {
      rating: average,
      reviewCount: nextCount,
      ratingTotal: nextTotal,
    });

    return {productId, rating: average, reviewCount: nextCount};
  });
}

module.exports = {
  orderContainsDeliveredProduct,
  submitReview,
};
