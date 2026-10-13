import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';

const directory = path.dirname(fileURLToPath(import.meta.url));
const rules = fs.readFileSync(path.join(directory, '..', 'firestore.rules'), 'utf8');
const projectId = 'craft-of-love-rules-test';

let environment;

const customer = { uid: 'customer-uid', id: 101, accountType: 'Customer' };
const otherCustomer = { uid: 'other-customer-uid', id: 102, accountType: 'Customer' };
const seller = { uid: 'seller-uid', id: 201, accountType: 'Seller' };
const otherSeller = { uid: 'other-seller-uid', id: 202, accountType: 'Seller' };

async function seedProfiles() {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const user of [customer, otherCustomer, seller, otherSeller]) {
      await db.collection('users').doc(user.uid).set({
        id: user.id,
        firebaseUid: user.uid,
        firstName: 'Test',
        lastName: 'User',
        email: `${user.uid}@example.test`,
        accountType: user.accountType,
        createdAt: '2026-10-07T00:00:00.000Z',
      });
    }
  });
}

function dbFor(user) {
  return environment.authenticatedContext(user.uid, {
    email: `${user.uid}@example.test`,
  }).firestore();
}

describe('C+ART Firestore rules', () => {
  before(async () => {
    environment = await initializeTestEnvironment({
      projectId,
      firestore: { rules },
    });
  });

  beforeEach(async () => {
    await environment.clearFirestore();
    await seedProfiles();
  });

  after(async () => {
    await environment.cleanup();
  });

  it('denies all unauthenticated reads', async () => {
    const db = environment.unauthenticatedContext().firestore();
    await assertFails(db.collection('products').get());
    await assertFails(db.collection('users').doc(customer.uid).get());
  });

  it('allows a user to update only their own profile', async () => {
    const own = dbFor(customer).collection('users').doc(customer.uid);
    const other = dbFor(customer).collection('users').doc(otherCustomer.uid);
    await assertSucceeds(own.update({ firstName: 'Updated' }));
    await assertSucceeds(own.update({
      notificationPreferences: {
        pushEnabled: true,
        emailEnabled: false,
        orderUpdates: false,
        promoOffers: true,
      },
    }));
    await assertFails(own.update({
      notificationPreferences: {
        pushEnabled: 'yes',
        emailEnabled: false,
        orderUpdates: true,
        promoOffers: true,
      },
    }));
    await assertFails(other.update({ firstName: 'Taken over' }));
    await assertFails(own.update({ accountType: 'Seller' }));
    await assertFails(own.update({ email: 'unverified@example.test' }));
    await assertFails(
      dbFor(customer).collection('users').doc('forged-user').set({
        id: 999,
        firebaseUid: 'forged-user',
        firstName: 'Forged',
        lastName: 'User',
        email: 'forged@example.test',
        accountType: 'Seller',
      }),
    );
  });

  it('allows sellers to manage only their own products', async () => {
    const product = dbFor(seller).collection('products').doc('301');
    await environment.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('products').doc('301').set({
        id: 301,
        sellerId: seller.id,
        categoryId: 1,
        productName: 'Basket',
        description: 'Handmade',
        price: 500,
        stock: 4,
        rating: 0,
        ratingTotal: 0,
        reviewCount: 0,
        totalSold: 0,
      });
    });
    await assertSucceeds(product.update({ price: 550 }));
    await assertFails(
      dbFor(seller).collection('products').doc('302').set({
        id: 302,
        sellerId: seller.id,
        categoryId: 1,
        productName: 'Forged product',
        description: 'Direct write',
        price: 1,
        stock: 1,
        rating: 0,
        reviewCount: 0,
        totalSold: 0,
      }),
    );
    await assertFails(
      dbFor(otherSeller).collection('products').doc('301').update({ price: 1 }),
    );
    await assertFails(
      dbFor(customer).collection('products').doc('301').update({ stock: 0 }),
    );
  });

  it('denies all direct counter access', async () => {
    const counter = dbFor(customer).collection('counters').doc('users');
    await assertFails(counter.get());
    await assertFails(counter.set({ lastId: 999 }));
  });

  it('keeps seller verification applications private and server-owned', async () => {
    await environment.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('sellerVerificationApplications').doc(seller.uid).set({
        uid: seller.uid,
        address: '123 Private Street',
        payoutAccountName: 'Test Seller',
        status: 'under_review',
      });
    });

    const application = dbFor(seller)
      .collection('sellerVerificationApplications')
      .doc(seller.uid);
    await assertFails(application.get());
    await assertFails(application.update({ status: 'approved' }));
    await assertFails(
      dbFor(otherSeller).collection('sellerVerificationApplications').doc(seller.uid).get(),
    );
    await assertFails(
      dbFor(seller).collection('users').doc(seller.uid).update({
        sellerVerification: { status: 'approved', listingLimit: 999 },
      }),
    );
  });

  it('limits order access to its customer and included seller', async () => {
    const orderData = {
      id: 4001,
      customerId: customer.id,
      customerFirstName: 'Test',
      customerLastName: 'Customer',
      sellerIds: [seller.id],
      productIds: [301],
      items: [{ productId: 301, sellerId: seller.id, quantity: 1, itemPrice: 500 }],
      total: 500,
      status: 'Pending',
      paymentMethod: 'Cash on Delivery',
      paymentStatus: 'Pay on delivery',
      orderDate: '2026-10-07T00:00:00.000Z',
      deliveryAddress: { fullName: 'Customer', phone: '09123456789', line1: 'Street' },
    };
    await environment.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('orders').doc('4001').set(orderData);
    });
    await assertSucceeds(dbFor(customer).collection('orders').doc('4001').get());
    await assertSucceeds(dbFor(seller).collection('orders').doc('4001').get());
    await assertFails(dbFor(otherCustomer).collection('orders').doc('4001').get());
    await assertFails(dbFor(otherSeller).collection('orders').doc('4001').get());
  });

  it('requires customer and seller order queries to include their scope', async () => {
    await environment.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('orders').doc('4001').set({
        id: 4001,
        customerId: customer.id,
        sellerIds: [seller.id],
        productIds: [301],
        items: [],
        total: 500,
        status: 'Pending',
        deliveryAddress: { line1: 'Street' },
      });
    });

    await assertSucceeds(
      dbFor(customer).collection('orders').where('customerId', '==', customer.id).get(),
    );
    await assertSucceeds(
      dbFor(seller).collection('orders').where('sellerIds', 'array-contains', seller.id).get(),
    );
    await assertFails(dbFor(customer).collection('orders').get());
    await assertFails(dbFor(seller).collection('orders').get());
  });

  it('prevents customers from creating orders for another account', async () => {
    await assertFails(
      dbFor(customer).collection('orders').doc('bad').set({
        id: 4002,
        customerId: otherCustomer.id,
        sellerIds: [seller.id],
        productIds: [301],
        items: [],
        total: 0,
        status: 'Pending',
        deliveryAddress: {},
      }),
    );
  });

  it('denies direct order creation and updates for customers and sellers', async () => {
    const order = {
      id: 4003,
      customerId: customer.id,
      sellerIds: [seller.id],
      productIds: [301],
      items: [],
      total: 500,
      status: 'Pending',
      deliveryAddress: { line1: 'Street' },
    };
    await assertFails(dbFor(customer).collection('orders').doc('4003').set(order));
    await environment.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('orders').doc('4003').set(order);
    });
    await assertFails(
      dbFor(customer).collection('orders').doc('4003').update({ total: 1 }),
    );
    await assertFails(
      dbFor(seller).collection('orders').doc('4003').update({ status: 'Delivered' }),
    );
  });

  it('denies direct review and product-rating writes', async () => {
    await environment.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('products').doc('301').set({
        id: 301,
        sellerId: seller.id,
        categoryId: 1,
        productName: 'Basket',
        description: 'Handmade',
        price: 500,
        stock: 4,
        rating: 0,
        ratingTotal: 0,
        reviewCount: 0,
        totalSold: 0,
      });
    });
    const review = dbFor(customer).collection('reviews').doc('301_101');
    await assertFails(review.set({
      productId: 301,
      customerId: customer.id,
      rating: 5,
      comment: 'Excellent',
    }));
    await assertFails(
      dbFor(otherCustomer).collection('reviews').doc('301_101').update({ rating: 1 }),
    );
    await assertFails(
      dbFor(customer).collection('reviews').doc('bad-rating').set({
        productId: 301,
        customerId: customer.id,
        rating: 8,
      }),
    );
    await assertFails(
      dbFor(seller).collection('products').doc('301').update({ rating: 5 }),
    );
  });

  it('allows only recipients to read and mark notifications read', async () => {
    await environment.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('notifications').doc('notice-1').set({
        userId: customer.id,
        createdById: seller.id,
        title: 'Order update',
        body: 'Your order shipped.',
        type: 'order_status',
        relatedId: 4001,
        isRead: false,
      });
    });
    await assertSucceeds(dbFor(customer).collection('notifications').doc('notice-1').get());
    await assertFails(dbFor(otherCustomer).collection('notifications').doc('notice-1').get());
    await assertSucceeds(
      dbFor(customer).collection('notifications').doc('notice-1').update({ isRead: true }),
    );
    await assertFails(
      dbFor(customer).collection('notifications').doc('notice-1').update({ body: 'Changed' }),
    );
    await assertFails(
      dbFor(customer).collection('notifications').doc('forged-order').set({
        userId: seller.id,
        createdById: customer.id,
        title: 'Fake order',
        body: 'Forged notification',
        type: 'order',
        isRead: false,
      }),
    );
    await assertSucceeds(
      dbFor(seller).collection('notifications').doc('live-notice').set({
        userId: customer.id,
        createdById: seller.id,
        title: 'Shop is LIVE',
        body: 'Watch now',
        type: 'live',
        isRead: false,
      }),
    );
  });

  it('limits conversations to their two participants', async () => {
    const conversation = dbFor(customer).collection('conversations').doc('101_201');
    await assertSucceeds(conversation.set({
      participantIds: [customer.id, seller.id],
      lastMessageText: '',
      unreadCounts: {},
    }));
    await assertSucceeds(dbFor(seller).collection('conversations').doc('101_201').get());
    await assertFails(dbFor(otherCustomer).collection('conversations').doc('101_201').get());
  });

  it('allows only the issuing seller to manage a campaign', async () => {
    const campaign = dbFor(seller).collection('followerCampaigns').doc(String(seller.id));
    await assertSucceeds(campaign.set({
      sellerId: seller.id,
      status: 'active',
      type: 'percentage',
      value: 10,
      minimum: 500,
      maximum: 100,
      quantity: 50,
      claimed: 0,
      validDays: 7,
    }));
    await assertFails(
      dbFor(otherSeller).collection('followerCampaigns').doc(String(seller.id)).update({
        status: 'ended',
      }),
    );
    await assertFails(campaign.update({ claimed: 49 }));
  });

  it('denies direct follower and voucher mutations', async () => {
    await assertFails(
      dbFor(customer).collection('shopFollows').doc('101_201').set({
        followerId: customer.id,
        sellerId: seller.id,
      }),
    );
    await assertFails(
      dbFor(customer).collection('customerVouchers').doc('forged').set({
        campaignId: 'forged',
        customerId: customer.id,
        sellerId: seller.id,
        type: 'percentage',
        value: 100,
        minimum: 0,
        orderId: null,
      }),
    );
  });

  it('denies undeclared collections by default', async () => {
    const document = dbFor(seller).collection('adminSecrets').doc('secret');
    await assertFails(document.set({ value: 'private' }));
    await assertFails(document.get());
  });
});
