/**
 * Jest setup — runs before every test file (jest `setupFiles`).
 *
 * Initializes the Firebase Admin SDK exactly once so the function handlers'
 * lazy `getFirestore()` calls connect to the Firestore emulator. The emulator
 * host is injected via FIRESTORE_EMULATOR_HOST by `firebase emulators:exec`.
 * The project id is the offline demo project `demo-fond` (no credentials).
 */
import {getApps, initializeApp} from "firebase-admin/app";

if (getApps().length === 0) {
  initializeApp({projectId: "demo-fond"});
}
