/**
 * notifyPartner — HTTPS Callable (v2)
 *
 * Called by the client immediately after writing a status/message update
 * to Firestore. Fans out FCM push notifications to ALL of the partner's
 * registered devices, plus direct APNs widget pushes.
 *
 * Privacy: This function reads the caller's encrypted fields and forwards
 * them in the push payload so the receiving device's Notification Service
 * Extension can decrypt locally — no Firestore roundtrip needed on the
 * receiver side. Firebase only sees ciphertext (Base64 blobs).
 *
 * Push strategy: ALL types are sent as alert + mutable-content so the
 * Notification Service Extension (NSE) can intercept them. The NSE
 * decrypts, writes to App Group, and reloads widgets. For types that
 * shouldn't show a visible notification (status, promptAnswer), the NSE
 * suppresses the display. Widget push is delayed 500ms after FCM to
 * avoid a race condition where WidgetKit reads stale App Group data.
 *
 * Hot path: every status change and message triggers this.
 * minInstances: 1 eliminates cold starts for ~$3/month.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";
import {sendWidgetPushToAll} from "./apnsHelper";

// APNs secrets for direct widget push
// (stored via `firebase functions:secrets:set`)
const apnsKeyP8 = defineSecret("APNS_KEY_P8");
const apnsKeyId = defineSecret("APNS_KEY_ID");
const apnsTeamId = defineSecret("APNS_TEAM_ID");

/** Valid notification types. */
type NotifyType = "status" | "message" | "nudge" | "heartbeat" | "promptAnswer";

const VALID_TYPES: NotifyType[] = [
  "status", "message", "nudge", "heartbeat", "promptAnswer",
];

/** Types that show a visible alert to the user (NSE keeps the display). */
const VISIBLE_ALERT_TYPES: NotifyType[] = ["message", "nudge", "heartbeat"];

/**
 * Notification body copy per type. Used as the initial alert body in the
 * push payload. For visible types, the NSE may replace this with decrypted
 * content. For non-visible types, the NSE suppresses the notification.
 */
const ALERT_BODY: Record<NotifyType, string> = {
  message: "New message from your person 💛",
  nudge: "Your person is thinking of you 💛",
  heartbeat: "Your person sent you a heartbeat ❤️",
  status: "Your person updated their status",
  promptAnswer: "Your person answered today's prompt",
};

/** Encrypted fields to forward from the caller's Firestore doc. */
const ENCRYPTED_FIELDS = [
  "encryptedStatus",
  "encryptedMessage",
  "encryptedName",
  "encryptedHeartbeat",
  "encryptedLocation",
  "encryptedPromptAnswer",
] as const;

/** Small delay (ms) before sending widget push, giving the NSE time to
 *  decrypt and write to App Group before WidgetKit reads it. */
const WIDGET_PUSH_DELAY_MS = 500;

interface NotifyPartnerData {
  type: NotifyType;
}

export const notifyPartner = onCall(
  {
    region: "us-central1",
    minInstances: 1,
    maxInstances: 10,
    secrets: [apnsKeyP8, apnsKeyId, apnsTeamId],
  },
  async (request) => {
    // 1. Verify authentication
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const callerUid = request.auth.uid;
    const data = request.data as NotifyPartnerData;

    if (!data.type || !VALID_TYPES.includes(data.type)) {
      throw new HttpsError(
        "invalid-argument",
        `type must be one of: ${VALID_TYPES.join(", ")}.`
      );
    }

    const db = getFirestore();

    // 2. Look up caller's user doc to get partnerUid
    const callerDoc = await db.collection("users").doc(callerUid).get();
    if (!callerDoc.exists) {
      throw new HttpsError("not-found", "User document not found.");
    }

    const callerData = callerDoc.data()!;
    const partnerUid = callerData.partnerUid as string | undefined;
    if (!partnerUid) {
      throw new HttpsError(
        "failed-precondition", "Not connected to a partner."
      );
    }

    // 2b. Extract caller's encrypted fields to include in push payload.
    //     These are forwarded as-is (ciphertext) — the receiving device's
    //     Notification Service Extension decrypts them locally.
    const encryptedPayload: Record<string, string> = {};
    for (const field of ENCRYPTED_FIELDS) {
      const value = callerData[field];
      if (typeof value === "string" && value.length > 0) {
        encryptedPayload[field] = value;
      }
    }

    // 3. Read partner's devices subcollection
    const devicesSnapshot = await db
      .collection("users")
      .doc(partnerUid)
      .collection("devices")
      .get();

    if (devicesSnapshot.empty) {
      logger.warn(`Partner ${partnerUid} has no registered devices.`);
      return {success: true, devicesNotified: 0, widgetsNotified: 0};
    }

    // 4. Collect tokens
    const messaging = getMessaging();
    const fcmTokens: string[] = [];
    const widgetTokens: string[] = [];

    devicesSnapshot.forEach((doc) => {
      const device = doc.data();
      if (device.fcmToken) fcmTokens.push(device.fcmToken);
      if (device.widgetPushToken) widgetTokens.push(device.widgetPushToken);
    });

    let devicesNotified = 0;
    let widgetsNotified = 0;

    // 5a. Send to FCM tokens (app notification)
    //
    // ALL types are sent as alert + mutable-content so the Notification
    // Service Extension (NSE) intercepts them. The NSE decrypts the
    // encrypted payload fields, writes plaintext to App Group, and
    // reloads widgets — even when the main app is terminated.
    //
    // For types that shouldn't show a visible notification (status,
    // promptAnswer), the NSE suppresses the display by clearing the
    // alert title/body before calling the content handler.
    if (fcmTokens.length > 0) {
      const isVisible = VISIBLE_ALERT_TYPES.includes(data.type);
      const alertBody = ALERT_BODY[data.type];

      const fcmPayload = {
        tokens: fcmTokens,
        data: {
          type: data.type,
          senderUid: callerUid,
          timestamp: new Date().toISOString(),
          // Forward caller's encrypted fields so receiver can decrypt
          // locally without a Firestore roundtrip.
          ...encryptedPayload,
        },
        apns: {
          headers: {
            "apns-priority": "10",
            // All types are alert pushes now (required for NSE)
            "apns-push-type": "alert",
          },
          payload: {
            aps: {
              "alert": {
                title: "Fond",
                body: alertBody,
              },
              // mutable-content: required for NSE interception
              "mutable-content": 1,
              // content-available: also wake main app as fallback
              "content-available": 1,
              // Sound only for user-visible types
              ...(isVisible ? {"sound": "default"} : {}),
              // Category lets iOS and the user control notification
              // grouping and settings per type
              "category": `fond.${data.type}`,
            },
          },
        },
      };

      try {
        const response = await messaging.sendEachForMulticast(fcmPayload);
        devicesNotified += response.successCount;

        if (response.failureCount > 0) {
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              logger.warn(
                `FCM send failed for token index ${idx}:`, resp.error
              );
            }
          });
        }
      } catch (err) {
        logger.error("FCM multicast error:", err);
      }
    }

    // 5b. Send widget push via direct APNs (WidgetKit reload)
    // Widget push tokens are raw APNs tokens — FCM can't send these.
    // We send directly to APNs with push type "widgets".
    //
    // IMPORTANT: Delayed by 500ms after FCM send completes. This gives
    // the Notification Service Extension time to decrypt the FCM payload
    // and write fresh data to App Group BEFORE WidgetKit calls
    // getTimeline() in response to this widget push. Without the delay,
    // WidgetKit reads stale data (race condition).
    if (widgetTokens.length > 0) {
      const keyP8 = apnsKeyP8.value();
      const keyId = apnsKeyId.value();
      const teamId = apnsTeamId.value();

      if (keyP8 && keyId && teamId) {
        // Delay widget push to avoid race with NSE
        await new Promise((resolve) =>
          setTimeout(resolve, WIDGET_PUSH_DELAY_MS)
        );

        try {
          // TODO: Set sandbox=false for production/TestFlight builds
          widgetsNotified = await sendWidgetPushToAll(
            widgetTokens, keyP8, keyId, teamId, /* sandbox= */ true
          );
        } catch (err) {
          logger.error("APNs widget push error:", err);
        }
      } else {
        logger.warn(
          "APNs secrets not configured." +
          " Run: firebase functions:" +
          "secrets:set APNS_KEY_P8 / " +
          "APNS_KEY_ID / APNS_TEAM_ID"
        );
      }
    }

    logger.info(
      `notifyPartner: ${callerUid} → ` +
      `${partnerUid}, type=${data.type}, ` +
      `devices=${devicesNotified}, ` +
      `widgets=${widgetsNotified}, ` +
      `payloadFields=${Object.keys(encryptedPayload).length}`
    );

    return {success: true, devicesNotified, widgetsNotified};
  }
);
