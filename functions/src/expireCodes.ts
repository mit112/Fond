/**
 * expireCodes — Scheduled Function (v2)
 *
 * Runs every 5 minutes to clean up expired and unclaimed pairing codes
 * from the `codes/` collection. Firestore has no native TTL, so this
 * scheduled function handles garbage collection.
 *
 * Cost: 288 invocations/day — well within free tier.
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

export const expireCodes = onSchedule(
  {
    schedule: "every 5 minutes",
    region: "us-central1",
    timeoutSeconds: 60,
  },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();

    // Query expired, unclaimed codes
    const expiredSnapshot = await db
      .collection("codes")
      .where("expiresAt", "<", now)
      .where("claimed", "==", false)
      .get();

    if (expiredSnapshot.empty) {
      logger.info("expireCodes: No expired codes to clean up.");
      return;
    }

    // Batch delete (max 500 per batch — more than enough)
    const batch = db.batch();
    expiredSnapshot.forEach((doc) => {
      batch.delete(doc.ref);
    });

    await batch.commit();
    logger.info(
      `expireCodes: Deleted ${expiredSnapshot.size} expired code(s).`
    );
  }
);
