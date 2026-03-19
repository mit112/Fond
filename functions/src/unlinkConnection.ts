/**
 * unlinkConnection — HTTPS Callable (v2)
 *
 * Atomically disconnects two users. Uses a Firestore batch write to:
 * 1. Deactivate the connection document
 * 2. Clear both users' connection-related fields
 * 3. Send push notification + widget push to the partner's devices
 *
 * Must be a Cloud Function (not client-side) because it modifies
 * BOTH users' documents in a single atomic operation.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret, defineBoolean} from "firebase-functions/params";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";
import {sendWidgetPushToAll} from "./apnsHelper";

// APNs config
const apnsSandbox = defineBoolean("APNS_SANDBOX", {default: false});

// APNs secrets for widget push
const apnsKeyP8 = defineSecret("APNS_KEY_P8");
const apnsKeyId = defineSecret("APNS_KEY_ID");
const apnsTeamId = defineSecret("APNS_TEAM_ID");

export const unlinkConnection = onCall(
  {
    region: "us-central1",
    secrets: [apnsKeyP8, apnsKeyId, apnsTeamId],
  },
  async (request) => {
    // 1. Verify authentication
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const callerUid = request.auth.uid;
    const db = getFirestore();

    // 2. Read caller's user doc
    const callerDoc = await db.collection("users").doc(callerUid).get();
    if (!callerDoc.exists) {
      throw new HttpsError("not-found", "User document not found.");
    }

    const callerData = callerDoc.data() as {
      connectionId?: string;
      partnerUid?: string;
    };
    const connectionId = callerData.connectionId;
    const partnerUid = callerData.partnerUid;

    if (!connectionId || !partnerUid) {
      throw new HttpsError(
        "failed-precondition", "Not connected to a partner."
      );
    }

    // 3. Verify connection exists and is active
    const connectionDoc = await db
      .collection("connections")
      .doc(connectionId)
      .get();
    if (!connectionDoc.exists || !connectionDoc.data()?.isActive) {
      throw new HttpsError(
        "failed-precondition", "Connection is not active."
      );
    }

    // 4. Atomic batch write: deactivate connection + clear both user docs
    const clearFields = {
      connectionId: FieldValue.delete(),
      partnerUid: FieldValue.delete(),
      encryptedName: FieldValue.delete(),
      encryptedStatus: FieldValue.delete(),
      encryptedMessage: FieldValue.delete(),
    };

    const batch = db.batch();

    // Deactivate the connection
    batch.update(db.collection("connections").doc(connectionId), {
      isActive: false,
    });

    // Clear caller's fields
    batch.update(db.collection("users").doc(callerUid), clearFields);

    // Clear partner's fields
    batch.update(db.collection("users").doc(partnerUid), clearFields);

    await batch.commit();

    // 5. Send push notifications to partner's devices
    try {
      const partnerDevices = await db
        .collection("users")
        .doc(partnerUid)
        .collection("devices")
        .get();

      const fcmTokens: string[] = [];
      const widgetTokens: string[] = [];

      partnerDevices.forEach((doc) => {
        const device = doc.data();
        if (device.fcmToken) fcmTokens.push(device.fcmToken);
        if (device.widgetPushToken) widgetTokens.push(device.widgetPushToken);
      });

      // 5a. FCM push (app notification)
      // mutable-content: 1 so the NSE can intercept and clear App Group
      if (fcmTokens.length > 0) {
        const messaging = getMessaging();
        await messaging.sendEachForMulticast({
          tokens: fcmTokens,
          data: {
            type: "unlink",
            timestamp: new Date().toISOString(),
          },
          apns: {
            headers: {
              "apns-priority": "10",
              "apns-push-type": "alert",
            },
            payload: {
              aps: {
                "alert": {
                  title: "Fond",
                  body: "Your connection has ended.",
                },
                "sound": "default",
                "mutable-content": 1,
                "content-available": 1,
                "category": "fond.unlink",
              },
            },
          },
        });
      }

      // 5b. Widget push via direct APNs
      if (widgetTokens.length > 0) {
        const keyP8 = apnsKeyP8.value();
        const keyId = apnsKeyId.value();
        const teamId = apnsTeamId.value();

        if (keyP8 && keyId && teamId) {
          await sendWidgetPushToAll(
            widgetTokens, keyP8, keyId, teamId, apnsSandbox.value()
          );
        }
      }
    } catch (err) {
      // Push failure shouldn't fail the unlink operation
      logger.error("Failed to notify partner of unlink:", err);
    }

    logger.info(
      `unlinkConnection: ${callerUid} unlinked from ${partnerUid}, ` +
      `connection=${connectionId}`
    );

    return {success: true};
  }
);
