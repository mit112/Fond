/**
 * apnsHelper — Direct APNs push for WidgetKit updates.
 *
 * FCM can't send widget push notifications because:
 * 1. Widget push tokens are raw APNs device tokens (not FCM tokens)
 * 2. Widget pushes require `apns-push-type: widgets`
 * 3. The APNs topic must be `{bundleId}.push-type.widgets`
 *
 * This helper signs a JWT with the .p8 key and sends HTTP/2
 * directly to APNs. Uses only built-in Node.js modules.
 *
 * Setup: Store secrets via Firebase CLI:
 *   firebase functions:secrets:set APNS_KEY_P8
 *   firebase functions:secrets:set APNS_KEY_ID
 *   firebase functions:secrets:set APNS_TEAM_ID
 */

import * as crypto from "crypto";
import * as http2 from "http2";
import * as logger from "firebase-functions/logger";

const APNS_HOST_PROD = "api.push.apple.com";
const APNS_HOST_SANDBOX = "api.sandbox.push.apple.com";
const BUNDLE_ID = "com.mitsheth.Fond";
const WIDGET_TOPIC = `${BUNDLE_ID}.push-type.widgets`;

// JWT cache — APNs JWTs are valid for up to 60 minutes.
// We cache for 50 minutes to avoid edge-case expiry.
let cachedJwt: string | null = null;
let cachedJwtTimestamp = 0;
const JWT_TTL_MS = 50 * 60 * 1000;

/**
 * Creates a JWT for APNs token-based auth (ES256).
 * @param {string} keyP8 .p8 private key contents
 * @param {string} keyId Key ID from Apple Developer
 * @param {string} teamId Team ID
 * @return {string} Signed JWT string
 */
function createApnsJwt(
  keyP8: string, keyId: string, teamId: string
): string {
  const now = Math.floor(Date.now() / 1000);

  if (cachedJwt && Date.now() - cachedJwtTimestamp < JWT_TTL_MS) {
    return cachedJwt;
  }

  const header = Buffer.from(JSON.stringify({
    alg: "ES256",
    kid: keyId,
  })).toString("base64url");

  const payload = Buffer.from(JSON.stringify({
    iss: teamId,
    iat: now,
  })).toString("base64url");

  const signingInput = `${header}.${payload}`;
  const signer = crypto.createSign("SHA256");
  signer.update(signingInput);
  const derSignature = signer.sign(keyP8);

  const rawSignature = derToRaw(derSignature);
  const signature = rawSignature.toString("base64url");

  cachedJwt = `${signingInput}.${signature}`;
  cachedJwtTimestamp = Date.now();

  return cachedJwt;
}

/**
 * Converts DER-encoded ECDSA signature to raw r||s (64 bytes).
 * @param {Buffer} derSig DER-encoded signature
 * @return {Buffer} Raw 64-byte r||s signature
 */
function derToRaw(derSig: Buffer): Buffer {
  // DER: 0x30 [len] 0x02 [rLen] [r] 0x02 [sLen] [s]
  let offset = 2;
  const seqLen = derSig[1] as number;
  if (seqLen > 0x80) {
    offset += seqLen - 0x80;
  }

  offset += 1; // skip 0x02
  const rLen = derSig[offset] as number;
  offset += 1;
  const rStart = offset;
  offset += rLen;

  offset += 1; // skip 0x02
  const sLen = derSig[offset] as number;
  offset += 1;
  const sStart = offset;

  const raw = Buffer.alloc(64);
  const r = derSig.subarray(rStart, rStart + rLen);
  const s = derSig.subarray(sStart, sStart + sLen);

  if (r.length === 33 && r[0] === 0) {
    r.subarray(1).copy(raw, 0);
  } else {
    r.copy(raw, 32 - r.length);
  }

  if (s.length === 33 && s[0] === 0) {
    s.subarray(1).copy(raw, 32);
  } else {
    s.copy(raw, 64 - s.length);
  }

  return raw;
}

/**
 * Sends a widget push to a single APNs device token.
 * @param {string} deviceToken Hex APNs token
 * @param {string} keyP8 .p8 private key contents
 * @param {string} keyId Key ID from Apple
 * @param {string} teamId Team ID
 * @param {boolean} sandbox Use sandbox APNs host
 * @return {Promise<boolean>} true if accepted by APNs
 */
async function sendWidgetPush(
  deviceToken: string,
  keyP8: string,
  keyId: string,
  teamId: string,
  sandbox = true,
): Promise<boolean> {
  const jwt = createApnsJwt(keyP8, keyId, teamId);
  const host = sandbox ? APNS_HOST_SANDBOX : APNS_HOST_PROD;

  return new Promise((resolve) => {
    const client = http2.connect(`https://${host}`);

    client.on("error", (err) => {
      logger.error("[APNs] Connection error:", err.message);
      client.close();
      resolve(false);
    });

    const payload = JSON.stringify({
      aps: {"content-changed": true},
    });

    const headers = {
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      "authorization": `bearer ${jwt}`,
      "apns-push-type": "widgets",
      "apns-topic": WIDGET_TOPIC,
      "apns-priority": "5",
    };

    const req = client.request(headers);
    let status = 0;
    let body = "";

    req.on("response", (hdrs) => {
      status = hdrs[":status"] as number;
    });

    req.on("data", (chunk: Buffer) => {
      body += chunk.toString();
    });

    req.on("end", () => {
      client.close();
      if (status === 200) {
        resolve(true);
      } else {
        const tk = deviceToken.substring(0, 8);
        logger.warn(
          "[APNs] Widget push failed " +
          `${tk}...: ${status} ${body}`
        );
        resolve(false);
      }
    });

    req.on("error", (err) => {
      logger.error("[APNs] Request error:", err.message);
      client.close();
      resolve(false);
    });

    req.setTimeout(10000, () => {
      logger.warn("[APNs] Request timed out");
      req.close();
      client.close();
      resolve(false);
    });

    req.write(payload);
    req.end();
  });
}

/**
 * Sends widget push to multiple tokens in parallel.
 * @param {string[]} deviceTokens Hex APNs tokens
 * @param {string} keyP8 .p8 private key contents
 * @param {string} keyId Key ID from Apple
 * @param {string} teamId Team ID
 * @param {boolean} sandbox Use sandbox APNs host
 * @return {Promise<number>} Count of successful pushes
 */
export async function sendWidgetPushToAll(
  deviceTokens: string[],
  keyP8: string,
  keyId: string,
  teamId: string,
  sandbox = true,
): Promise<number> {
  if (deviceTokens.length === 0) return 0;

  const results = await Promise.all(
    deviceTokens.map((token) =>
      sendWidgetPush(token, keyP8, keyId, teamId, sandbox)
    )
  );

  return results.filter((ok) => ok).length;
}
