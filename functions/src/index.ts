/**
 * Fond — Cloud Functions Entry Point
 *
 * All functions use the v2 API (firebase-functions ^7.0.0).
 * Region: us-central1 (matches Firestore location).
 */

import {initializeApp} from "firebase-admin/app";
import {setGlobalOptions} from "firebase-functions/v2";

// Initialize Firebase Admin SDK (must be first)
initializeApp();

// Global options for all functions
setGlobalOptions({maxInstances: 10});

// Re-export all functions
export {notifyPartner} from "./notifyPartner.js";
export {expireCodes} from "./expireCodes.js";
export {unlinkConnection} from "./unlinkConnection.js";
export {linkUsers} from "./linkUsers.js";
