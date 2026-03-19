/**
 * linkUsers — HTTPS Callable (v2)
 *
 * Claims a pairing code and links two users together.
 * Must run server-side because the claimer needs to write to the
 * creator's user doc (which client-side rules correctly forbid).
 *
 * Firestore transaction: claim code + create connection + update both users.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

interface LinkUsersData {
  /** The 6-character pairing code to claim. */
  code: string;
}

export const linkUsers = onCall(
  {
    region: "us-central1",
    maxInstances: 10,
  },
  async (request) => {
    // 1. Verify authentication
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const claimerUid = request.auth.uid;
    const data = request.data as LinkUsersData;

    if (!data.code || typeof data.code !== "string") {
      throw new HttpsError("invalid-argument", "code is required.");
    }

    const normalized = data.code.toUpperCase().trim();
    if (normalized.length !== 6) {
      throw new HttpsError("invalid-argument", "Code must be 6 characters.");
    }

    const db = getFirestore();
    const codeRef = db.collection("codes").doc(normalized);
    const connectionRef = db.collection("connections").doc();
    const connectionId = connectionRef.id;

    // Run all reads and writes inside a transaction to eliminate TOCTOU races.
    // If two requests try to claim the same code concurrently, Firestore will
    // retry the loser and it will see claimed === true on the second attempt.
    const {creatorUid} = await db.runTransaction(async (txn) => {
      // 2. Read all documents inside the transaction
      const codeDoc = await txn.get(codeRef);

      if (!codeDoc.exists) {
        throw new HttpsError(
          "not-found",
          "Invalid or expired code. Ask your partner for a new one."
        );
      }

      const codeData = codeDoc.data()!;
      const creator = codeData.creatorUid as string;

      if (codeData.claimed === true) {
        throw new HttpsError(
          "already-exists", "This code has already been used."
        );
      }

      const expiresAt = codeData.expiresAt?.toDate();
      if (expiresAt && expiresAt < new Date()) {
        throw new HttpsError(
          "deadline-exceeded",
          "This code has expired. Ask your partner for a new one."
        );
      }

      if (creator === claimerUid) {
        throw new HttpsError(
          "invalid-argument", "You can't pair with yourself."
        );
      }

      // 3. Check neither user is already connected
      const creatorDocRef = db.collection("users").doc(creator);
      const claimerDocRef = db.collection("users").doc(claimerUid);
      const [creatorDoc, claimerDoc] = await Promise.all([
        txn.get(creatorDocRef),
        txn.get(claimerDocRef),
      ]);

      if (creatorDoc.data()?.partnerUid) {
        throw new HttpsError(
          "failed-precondition",
          "The code creator is already connected to someone."
        );
      }
      if (claimerDoc.data()?.partnerUid) {
        throw new HttpsError(
          "failed-precondition", "You're already connected to someone."
        );
      }

      // 4. All preconditions passed — write atomically

      // Claim the code
      txn.update(codeRef, {claimed: true});

      // Create connection
      txn.set(connectionRef, {
        user1: creator,
        user2: claimerUid,
        isActive: true,
        createdAt: FieldValue.serverTimestamp(),
      });

      // Update creator's user doc
      txn.set(
        creatorDocRef,
        {
          connectionId: connectionId,
          partnerUid: claimerUid,
          lastUpdatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      // Update claimer's user doc
      txn.set(
        claimerDocRef,
        {
          connectionId: connectionId,
          partnerUid: creator,
          lastUpdatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      return {creatorUid: creator};
    });

    logger.info(
      `linkUsers: ${claimerUid} claimed code ${normalized}, ` +
      `connected with ${creatorUid}, connection=${connectionId}`
    );

    return {
      success: true,
      connectionId: connectionId,
      partnerUid: creatorUid,
    };
  }
);
