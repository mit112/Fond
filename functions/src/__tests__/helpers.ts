/**
 * Shared test helpers for the Cloud Functions emulator suites.
 *
 * `clearFirestore()` wipes all documents between tests via the emulator's
 * REST clear endpoint — required because `jest --runInBand` shares one
 * emulator instance across every suite.
 */
import {getFirestore, Timestamp} from "firebase-admin/firestore";

export const PROJECT_ID = "demo-fond";

/** Firestore admin handle (bypasses security rules — used only for seeding). */
export function db(): FirebaseFirestore.Firestore {
  return getFirestore();
}

/** Deletes every document in the emulator so each test starts clean. */
export async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) {
    throw new Error(
      "FIRESTORE_EMULATOR_HOST is not set — run via `firebase emulators:exec`."
    );
  }
  const url =
    `http://${host}/emulator/v1/projects/${PROJECT_ID}` +
    "/databases/(default)/documents";
  const res = await fetch(url, {method: "DELETE"});
  if (!res.ok) {
    throw new Error(`Failed to clear Firestore emulator: ${res.status}`);
  }
}

/** A Timestamp `ms` milliseconds in the future (default 1 hour). */
export function futureTimestamp(ms = 60 * 60 * 1000): Timestamp {
  return Timestamp.fromMillis(Date.now() + ms);
}

/** A Timestamp `ms` milliseconds in the past (default 1 hour). */
export function pastTimestamp(ms = 60 * 60 * 1000): Timestamp {
  return Timestamp.fromMillis(Date.now() - ms);
}
