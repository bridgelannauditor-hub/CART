// Development only: sends a signed verification result to a LOCAL
// verification-webhook function, so each outcome can be tested without a real
// provider. Refuses any non-local URL.
//
//   node --env-file=.env simulate-verification-result.mjs <provider_session_id> verified
//   Outcomes: verified | needs_retry | under_review | rejected

import {createHmac, randomUUID} from 'node:crypto';
import process from 'node:process';

const [sessionId, outcome, reasonCode] = process.argv.slice(2);
const outcomes = ['verified', 'needs_retry', 'under_review', 'rejected'];
if (!sessionId || !outcomes.includes(outcome)) {
  console.error(`Usage: simulate-verification-result.mjs <provider_session_id> ${outcomes.join('|')} [reason_code]`);
  process.exit(1);
}

const url = process.env.VERIFICATION_WEBHOOK_URL;
const secret = process.env.VERIFICATION_WEBHOOK_SECRET;
if (!url || !secret) throw new Error('VERIFICATION_WEBHOOK_URL and VERIFICATION_WEBHOOK_SECRET are required.');
if (!['localhost', '127.0.0.1'].includes(new URL(url).hostname)) {
  throw new Error('Refusing to send simulated results to a non-local webhook.');
}

const passed = outcome === 'verified';
const body = JSON.stringify({
  event_id: randomUUID(),
  session_id: sessionId,
  outcome,
  reason_code: reasonCode ?? (passed ? null : 'simulated'),
  checks: {document: passed, liveness: passed, face_match: passed},
});
const timestamp = Math.floor(Date.now() / 1000).toString();
const signature = createHmac('sha256', secret).update(`${timestamp}.${body}`).digest('hex');

const response = await fetch(url, {
  method: 'POST',
  headers: {
    'content-type': 'application/json',
    'x-signature-timestamp': timestamp,
    'x-signature': signature,
  },
  body,
});
console.log(`Webhook responded ${response.status}.`);
