const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

const checkout = require("./src/checkout");
const reviews = require("./src/reviews");
const resources = require("./src/resources");

initializeApp();
const db = getFirestore();
const callableOptions = {region: "asia-southeast1"};

function requireAuthentication(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }
  return request.auth.uid;
}

function asHttpsError(error) {
  if (error instanceof HttpsError) throw error;
  if (error instanceof checkout.CheckoutError) {
    throw new HttpsError(error.code, error.message);
  }
  console.error(error);
  throw new HttpsError("internal", "The request could not be completed.");
}

exports.placeOrder = onCall(callableOptions, async (request) => {
  try {
    return await checkout.placeOrder(db, requireAuthentication(request), request.data);
  } catch (error) {
    return asHttpsError(error);
  }
});

exports.cancelOrderItem = onCall(callableOptions, async (request) => {
  try {
    return await checkout.cancelOrderItem(
      db,
      requireAuthentication(request),
      request.data,
    );
  } catch (error) {
    return asHttpsError(error);
  }
});

exports.updateSellerOrder = onCall(callableOptions, async (request) => {
  try {
    return await checkout.updateSellerOrder(
      db,
      requireAuthentication(request),
      request.data,
    );
  } catch (error) {
    return asHttpsError(error);
  }
});

exports.toggleShopFollow = onCall(callableOptions, async (request) => {
  try {
    return await checkout.toggleShopFollow(
      db,
      requireAuthentication(request),
      request.data,
    );
  } catch (error) {
    return asHttpsError(error);
  }
});

exports.submitReview = onCall(callableOptions, async (request) => {
  try {
    return await reviews.submitReview(
      db,
      requireAuthentication(request),
      request.data,
    );
  } catch (error) {
    return asHttpsError(error);
  }
});

exports.ensureUserProfile = onCall(callableOptions, async (request) => {
  try {
    return await resources.ensureUserProfile(
      db,
      requireAuthentication(request),
      request.auth.token.email,
      request.auth.token.firebase?.sign_in_provider,
      request.data,
    );
  } catch (error) {
    return asHttpsError(error);
  }
});

exports.createProduct = onCall(callableOptions, async (request) => {
  try {
    return await resources.createProduct(
      db,
      requireAuthentication(request),
      request.data,
    );
  } catch (error) {
    return asHttpsError(error);
  }
});

exports._test = {...checkout, ...reviews, ...resources};
