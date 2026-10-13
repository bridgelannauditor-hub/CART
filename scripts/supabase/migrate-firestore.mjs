import {readFile} from 'node:fs/promises';
import process from 'node:process';
import {createHash} from 'node:crypto';

import {cert, initializeApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {createClient} from '@supabase/supabase-js';

const apply = process.argv.includes('--apply');
const required = ['FIREBASE_PROJECT_ID', 'FIREBASE_SERVICE_ACCOUNT'];
if (apply) required.push('SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY');
for (const name of required) {
  if (!process.env[name]) throw new Error(`${name} is required.`);
}

const serviceAccount = JSON.parse(
  await readFile(process.env.FIREBASE_SERVICE_ACCOUNT, 'utf8'),
);
initializeApp({
  credential: cert(serviceAccount),
  projectId: process.env.FIREBASE_PROJECT_ID,
});
const firestore = getFirestore();
const supabase = apply
  ? createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      {auth: {autoRefreshToken: false, persistSession: false}},
    )
  : null;

const counts = new Map();
const skipped = [];
const migratedOrderIds = new Set();

function timestamp(value) {
  if (value == null) return null;
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (typeof value === 'string') return value;
  if (value._seconds != null) return new Date(value._seconds * 1000).toISOString();
  return value;
}

function integer(value, fallback = null) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : fallback;
}

function number(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function uuid(value) {
  return typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value
    : undefined;
}

function stableUuid(value) {
  const existing = uuid(value);
  if (existing) return existing;
  if (!value) return undefined;
  const hex = createHash('sha256').update(String(value)).digest('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

function stablePositiveInteger(value) {
  if (!value) return undefined;
  const hex = createHash('sha256').update(String(value)).digest('hex');
  // Thirteen hex digits stay within JavaScript's safe-integer range.
  return Math.max(1, Number.parseInt(hex.slice(0, 13), 16));
}

function compact(row) {
  return Object.fromEntries(Object.entries(row).filter(([, value]) => value !== undefined));
}

async function docs(collectionPath) {
  return (await firestore.collection(collectionPath).get()).docs;
}

async function upsert(table, rows, onConflict = 'id') {
  counts.set(table, (counts.get(table) || 0) + rows.length);
  if (!apply || rows.length === 0) return;
  for (let offset = 0; offset < rows.length; offset += 250) {
    const batch = rows.slice(offset, offset + 250);
    const {error} = await supabase.from(table).upsert(batch, {
      onConflict,
      ignoreDuplicates: false,
    });
    if (error) throw new Error(`${table}: ${error.message}`);
  }
}

async function migrateProfiles() {
  const source = await docs('users');
  await upsert('profiles', source.map((doc) => {
    const value = doc.data();
    return compact({
      id: integer(value.id),
      legacy_firebase_uid: value.firebaseUid || doc.id,
      first_name: value.firstName || 'Customer',
      last_name: value.lastName || '',
      email: value.email || '',
      phone: value.phone || null,
      account_type: value.accountType === 'Seller' ? 'Seller' : 'Customer',
      shop_name: value.shopName || (value.accountType === 'Seller' ? 'Shop' : null),
      cover_image: value.coverImage || null,
      profile_image: value.profileImage || null,
      is_live: value.isLive === true,
      seller_verification: value.sellerVerification || null,
      notification_preferences: value.notificationPreferences || undefined,
      created_at: timestamp(value.createdAt) || new Date().toISOString(),
    });
  }).filter((row) => row.id != null));
  const searches = [];
  for (const doc of source) {
    const value = doc.data();
    const userId = integer(value.id);
    if (userId == null || !Array.isArray(value.recentSearches)) continue;
    for (const query of value.recentSearches) {
      const clean = String(query).trim();
      if (clean) searches.push({
        user_id: userId,
        query: clean,
        searched_at: timestamp(value.recentSearchesUpdatedAt) || new Date().toISOString(),
      });
    }
  }
  await upsert('search_history', searches, 'user_id,query');
}

async function migrateProducts() {
  const source = await docs('products');
  await upsert('products', source.map((doc) => {
    const value = doc.data();
    return compact({
      id: integer(value.id, integer(doc.id)),
      seller_id: integer(value.sellerId),
      category_id: integer(value.categoryId),
      category_group: value.categoryGroup || null,
      category_name: value.categoryName || null,
      product_name: value.productName || '',
      description: value.description || '',
      price: number(value.price),
      stock: integer(value.stock, 0),
      image: value.image || '',
      rating: number(value.rating),
      rating_total: number(value.ratingTotal, number(value.rating) * integer(value.reviewCount, 0)),
      review_count: integer(value.reviewCount, 0),
      total_sold: integer(value.totalSold, 0),
      craft_type: value.craftType || null,
      material: value.material || null,
      occasion: value.occasion || null,
      is_flash_sale: value.isFlashSale === true,
      discount_percent: integer(value.discountPercent, 0),
      free_shipping: value.freeShipping === true,
      cod_available: value.codAvailable === true,
      making_process: value.makingProcess || null,
      media: Array.isArray(value.media) ? value.media : [],
      tags: Array.isArray(value.tags) ? value.tags.map(String) : [],
      pricing_mode: value.pricingMode === 'per_image' ? 'per_image' : 'single',
      options: Array.isArray(value.options) ? value.options : [],
      created_at: timestamp(value.createdAt) || new Date().toISOString(),
    });
  }).filter((row) => row.id != null && row.seller_id != null && row.category_id != null));
}

async function migrateOrders() {
  const source = await docs('orders');
  const orders = [];
  const items = [];
  for (const doc of source) {
    const value = doc.data();
    const orderId = integer(value.id, integer(doc.id));
    if (orderId == null || integer(value.customerId) == null) continue;
    migratedOrderIds.add(orderId);
    const sourceItems = Array.isArray(value.items) ? value.items : [];
    orders.push(compact({
      id: orderId,
      customer_id: integer(value.customerId),
      seller_ids: Array.isArray(value.sellerIds) ? value.sellerIds.map(Number) : [...new Set(sourceItems.map((item) => integer(item.sellerId)).filter(Boolean))],
      product_ids: Array.isArray(value.productIds) ? value.productIds.map(Number) : [...new Set(sourceItems.map((item) => integer(item.productId)).filter(Boolean))],
      subtotal: number(value.subtotal, number(value.total)),
      discount: number(value.discount),
      total: number(value.total),
      status: value.status || 'Pending',
      payment_method: value.paymentMethod || 'Unknown',
      delivery_address: value.deliveryAddress || {},
      seller_fulfillment: value.sellerFulfillment || {},
      tracking: value.tracking || {},
      vouchers: Array.isArray(value.vouchers) ? value.vouchers : [],
      order_date: timestamp(value.orderDate) || timestamp(value.createdAt) || new Date().toISOString(),
      created_at: timestamp(value.createdAt) || timestamp(value.orderDate) || new Date().toISOString(),
      updated_at: timestamp(value.updatedAt) || undefined,
    }));
    sourceItems.forEach((item, index) => items.push(compact({
      id: integer(item.id, orderId * 1000 + index),
      order_id: orderId,
      product_id: integer(item.productId),
      seller_id: integer(item.sellerId),
      quantity: integer(item.quantity, 1),
      item_price: number(item.itemPrice, number(item.price)),
      product_name: item.productName || 'Product',
      product_image: item.productImage || '',
      option_id: item.optionId || null,
      option_name: item.optionName || null,
      option_image: item.optionImage || null,
      status: item.status || value.status || 'Pending',
      cancelled_at: timestamp(item.cancelledAt),
    })));
  }
  await upsert('orders', orders);
  await upsert('order_items', items.filter((row) => row.product_id != null && row.seller_id != null));
}

async function migrateReviews() {
  const source = await docs('reviews');
  await upsert('reviews', source.map((doc) => {
    const value = doc.data();
    return compact({
      product_id: integer(value.productId),
      customer_id: integer(value.customerId),
      rating: number(value.rating),
      comment: value.comment || null,
      customer_first_name: value.customerFirstName || '',
      customer_last_name: value.customerLastName || '',
      created_at: timestamp(value.createdAt) || new Date().toISOString(),
      updated_at: timestamp(value.updatedAt) || undefined,
    });
  }).filter((row) => row.product_id != null && row.customer_id != null), 'product_id,customer_id');
}

async function migrateSimpleCollection(sourceName, table, mapper, onConflict = 'id') {
  const source = await docs(sourceName);
  await upsert(table, source.map((doc) => mapper(doc.id, doc.data())).filter(Boolean), onConflict);
}

async function migrateConversations() {
  const source = await docs('conversations');
  for (const conversation of source) {
    const value = conversation.data();
    const conversationId = stableUuid(conversation.id);
    await upsert('conversations', [compact({
      id: conversationId,
      participant_ids: (value.participantIds || []).map(Number),
      last_message: value.lastMessage || null,
      last_message_date: timestamp(value.lastMessageDate),
      created_at: timestamp(value.createdAt) || new Date().toISOString(),
      updated_at: timestamp(value.updatedAt) || undefined,
    })]);
    const messageDocs = await conversation.ref.collection('messages').get();
    await upsert('messages', messageDocs.docs.map((doc) => {
      const message = doc.data();
      return compact({
        id: stableUuid(doc.id),
        conversation_id: conversationId,
        sender_id: integer(message.senderId),
        receiver_id: integer(message.receiverId),
        message_text: message.messageText || '',
        message_date: timestamp(message.messageDate) || timestamp(message.createdAt) || new Date().toISOString(),
        is_read: message.isRead === true,
        context_type: message.contextType || null,
        context_id: integer(message.contextId),
        context_name: message.contextName || null,
        context_image: message.contextImage || null,
        context_price: message.contextPrice == null ? null : number(message.contextPrice),
        message_type: message.messageType || 'text',
        media_url: message.mediaUrl || null,
        media_duration_ms: integer(message.mediaDurationMs),
        edited_at: timestamp(message.editedAt),
        reply_to_id: stableUuid(message.replyToId),
        reply_text: message.replyText || null,
        reply_type: message.replyType || null,
      });
    }).filter((row) => row.id && row.sender_id != null && row.receiver_id != null));
  }
}

async function migrateSellerVerificationApplications() {
  const profileDocs = await docs('users');
  const idByUid = new Map(profileDocs.map((doc) => [doc.id, integer(doc.data().id)]));
  await migrateSimpleCollection(
    'sellerVerificationApplications',
    'seller_verification_applications',
    (uid, value) => {
      const profileId = idByUid.get(uid);
      if (profileId == null) return null;
      return compact({
        profile_id: profileId,
        seller_type: value.sellerType,
        birth_date: value.birthDate,
        address: value.address,
        identity_document_type: value.identityDocumentType,
        payout_method: value.payoutMethod,
        payout_account_name: value.payoutAccountName,
        organization_name: value.organizationName || null,
        business_registration_number: value.businessRegistrationNumber || null,
        status: value.status || 'under_review',
        level: value.level || 'registered',
        listing_limit: integer(value.listingLimit, 5),
        submitted_at: timestamp(value.submittedAt) || new Date().toISOString(),
        reviewed_at: timestamp(value.reviewedAt),
      });
    },
    'profile_id',
  );
}

async function migrateLiveSessions() {
  const source = await docs('liveSessions');
  for (const session of source) {
    const value = session.data();
    const sessionId = stableUuid(session.id);
    const liveSession = compact({
      id: sessionId,
      seller_id: integer(value.sellerId),
      broadcast_id: value.broadcastId || session.id,
      title: value.shopName || 'LIVE',
      is_live: value.active === true,
      product_ids: Array.isArray(value.featuredProductIds) ? value.featuredProductIds.map(Number) : [],
      pinned_product_id: integer(value.pinnedProductId),
      comments_enabled: value.commentsEnabled !== false,
      reaction_counts: value.reactionCounts || {},
      started_at: timestamp(value.startedAt),
      ended_at: timestamp(value.endedAt),
      created_at: timestamp(value.startedAt) || new Date().toISOString(),
    });
    if (liveSession.seller_id == null) {
      skipped.push(`live session ${session.id}: missing sellerId`);
      continue;
    }
    await upsert('live_sessions', [liveSession]);
    const messageDocs = await session.ref.collection('messages').get();
    await upsert('live_messages', messageDocs.docs.map((doc) => {
      const message = doc.data();
      return compact({
        id: stableUuid(doc.id), session_id: sessionId,
        sender_id: integer(message.senderId), text: message.text || '',
        hidden: message.hidden === true,
        created_at: timestamp(message.createdAt) || new Date().toISOString(),
      });
    }).filter((row) => row.sender_id != null && row.text));
    const blockedDocs = await session.ref.collection('blockedUsers').get();
    await upsert('live_blocked_users', blockedDocs.docs.map((doc) => {
      const blocked = doc.data();
      return compact({
        session_id: sessionId,
        user_id: integer(blocked.userId, integer(doc.id)),
        created_at: timestamp(blocked.blockedAt) || new Date().toISOString(),
      });
    }).filter((row) => row.user_id != null), 'session_id,user_id');
  }
}

async function main() {
  console.log(apply ? 'APPLY mode: writing to Supabase.' : 'DRY RUN: reading Firebase only.');
  await migrateProfiles();
  await migrateSellerVerificationApplications();
  await migrateProducts();
  await migrateOrders();
  await migrateReviews();
  await migrateSimpleCollection('notifications', 'notifications', (id, value) => compact({
    id: stableUuid(id), user_id: integer(value.userId), created_by_id: integer(value.createdById),
    title: value.title || '', body: value.body || '', type: value.type || '',
    related_id: integer(value.relatedId), is_read: value.isRead === true,
    created_at: timestamp(value.createdAt) || timestamp(value.createdDate) || new Date().toISOString(),
  }));
  await migrateSimpleCollection('shopFollows', 'shop_follows', (_id, value) => compact({
    follower_id: integer(value.followerId), seller_id: integer(value.sellerId),
    created_at: timestamp(value.createdAt) || new Date().toISOString(),
  }), 'follower_id,seller_id');
  await migrateSimpleCollection('shopFollowHistory', 'shop_follow_history', (_id, value) => compact({
    customer_id: integer(value.customerId), seller_id: integer(value.sellerId),
    first_followed_at: timestamp(value.firstFollowedAt) || new Date().toISOString(),
  }), 'customer_id,seller_id');
  await migrateSimpleCollection('shopVisits', 'shop_visits', (id, value) => compact({
    id: integer(value.id, integer(id, stablePositiveInteger(id))),
    visitor_id: integer(value.visitorId), seller_id: integer(value.sellerId),
    created_at: timestamp(value.createdAt) || new Date().toISOString(),
  }));
  await migrateSimpleCollection('customerVouchers', 'customer_vouchers', (id, value) => {
    const orderId = integer(value.orderId);
    if (orderId != null && !migratedOrderIds.has(orderId)) {
      skipped.push(`voucher ${id}: cleared missing order reference ${orderId}`);
    }
    return compact({
      id, campaign_id: value.campaignId, customer_id: integer(value.customerId),
      seller_id: integer(value.sellerId), seller_name: value.sellerName || 'Shop', type: value.type,
      value: number(value.value), minimum: number(value.minimum), maximum: value.maximum == null ? null : number(value.maximum),
      claimed_at: timestamp(value.claimedAt) || new Date().toISOString(), expires_at: timestamp(value.expiresAt),
      order_id: migratedOrderIds.has(orderId) ? orderId : null,
      redeemed_at: timestamp(value.redeemedAt), revenue: number(value.revenue),
    });
  });
  await migrateSimpleCollection('followerCampaigns', 'follower_campaigns', (id, value) => compact({
    id: stableUuid(value.campaignId || id), campaign_id: value.campaignId || id,
    seller_id: integer(value.sellerId, integer(id)), type: value.type,
    value: number(value.value), minimum: number(value.minimum),
    maximum: value.maximum == null ? null : number(value.maximum),
    quantity: integer(value.quantity, 1), claimed: integer(value.claimed, 0),
    valid_days: integer(value.validDays, 1), status: value.status || 'active',
    starts_at: timestamp(value.startsAt), expires_at: timestamp(value.expiresAt),
    created_at: timestamp(value.createdAt) || new Date().toISOString(),
  }));
  await migrateConversations();
  await migrateLiveSessions();

  if (apply) {
    const {error} = await supabase.rpc('sync_migration_sequences');
    if (error) throw new Error(`sync_migration_sequences: ${error.message}`);
  }

  console.log('\nMigration inventory:');
  for (const [table, count] of [...counts.entries()].sort()) console.log(`  ${table}: ${count}`);
  if (skipped.length) {
    console.log('\nSkipped records:');
    skipped.forEach((entry) => console.log(`  ${entry}`));
  }
  console.log(apply ? '\nData copy complete. Do not cut over until validation passes.' : '\nDry run complete. Re-run with --apply after reviewing counts.');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
