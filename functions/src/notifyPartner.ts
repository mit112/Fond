/**
 * notifyPartner — HTTPS Callable (v2)
 *
 * Called by the client immediately after writing a status/message update
 * to Firestore. Fans out FCM push notifications to ALL of the partner's
 * registered devices, plus direct APNs widget pushes.
 *
 * This function does NOT read or decrypt any user content. It only knows
 * "user X updated" and pushes a signal to the partner's devices.
 * Privacy is preserved — Firebase never sees plaintext.
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

/** Valid notification types. Determines alert vs silent routing. */
type NotifyType = "status" | "message" | "nudge" | "heartbeat" | "promptAnswer";

const VALID_TYPES: NotifyType[] = [
  "status", "message", "nudge", "heartbeat", "promptAnswer",
];

/** Types that show a visible alert notification (not silent). */
const ALERT_TYPES: NotifyType[] = ["message", "nudge", "heartbeat"];

/** Notification body copy per alert type. Generic — no user content. */
const ALERT_BODY: Partial<Record<NotifyType, string>> = {
  message: "New message from your person 💛",
  nudge: "Your person is thinking of you 💛",
  heartbeat: "Your person sent you a heartbeat ❤️",
};

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

    const partnerUid = callerDoc.data()?.partnerUid as string | undefined;
    if (!partnerUid) {
      throw new HttpsError(
        "failed-precondition", "Not connected to a partner."
      );
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
    if (fcmTokens.length > 0) {
      const isAlert = ALERT_TYPES.includes(data.type);
      const alertBody = ALERT_BODY[data.type] ?? "Update from your person";

      const fcmPayload = {
        tokens: fcmTokens,
        data: {
          type: data.type,
          senderUid: callerUid,
          timestamp: new Date().toISOString(),
        },
        apns: {
          headers: {
            "apns-priority": "10", // Immediate delivery
            "apns-push-type": isAlert ? "alert" : "background",
          },
          payload: {
            aps: isAlert ?
              {
                "alert": {
                  title: "Fond",
                  body: alertBody,
                },
                "sound": "default",
                "mutable-content": 1,
              } :
              {
                // Silent push — status changes, prompt answers
                "content-available": 1,
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
    if (widgetTokens.length > 0) {
      const keyP8 = apnsKeyP8.value();
      const keyId = apnsKeyId.value();
      const teamId = apnsTeamId.value();

      if (keyP8 && keyId && teamId) {
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
      `widgets=${widgetsNotified}`
    );

    return {success: true, devicesNotified, widgetsNotified};
  }
);
