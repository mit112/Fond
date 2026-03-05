# Fond — Your Person, At a Glance

A privacy-first couples widget app for iOS 26, iPadOS 26, macOS Tahoe, and watchOS 26. Two people pair via a 6-character code and see each other's status, messages, heartbeat, and location distance — all updated in real time across home screen widgets, lock screen complications, and Apple Watch.

**Every piece of user content is end-to-end encrypted.** Firebase only sees ciphertext.

## Features

- **Real-time status sharing** — 16 statuses across Availability, Mood, Activity, and Love categories with color-coded emoji
- **Encrypted messaging** — Short messages delivered in under 2 seconds via push notification pipeline
- **Widget-first design** — 5 widget families (inline, circular, rectangular, small, medium) across iOS, iPadOS, macOS, and watchOS
- **End-to-end encryption** — X25519 key exchange + AES-256-GCM; symmetric keys synced via iCloud Keychain
- **Notification Service Extension** — Decrypts push payloads in <1ms without waking the main app
- **Heartbeat sharing** — Live BPM from Apple Watch via HealthKit integration
- **Location distance** — Privacy-rounded coordinates (~1km precision), encrypted before upload
- **Daily prompts** — Rotating relationship prompts both partners can answer
- **Liquid Glass UI** — iOS 26 design language with animated mesh gradient backgrounds, glass-tier hierarchy, and spring animations
- **watchOS companion** — Full bidirectional support: view partner status, send nudges and heartbeats

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Client Layer                         │
│                                                             │
│  iOS App ←──→ watchOS App       Widgets (5 families)        │
│     │         (WatchConnectivity)    ↑                      │
│     │                                │ App Group            │
│     ├── AuthManager (@Observable)    │ UserDefaults         │
│     ├── EncryptionManager            │ (plaintext)          │
│     ├── FirebaseManager              │                      │
│     ├── PushManager ─────────────────┤                      │
│     └── KeychainManager              │                      │
│         (iCloud Keychain sync)       │                      │
│                                      │                      │
│  NSE ───── decrypt payload ──────────┘                      │
│  (no Firebase SDK, <1ms)                                    │
└────────────────────────┬────────────────────────────────────┘
                         │ Firestore + HTTPS Callable
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   Firebase (fond-cf7f5)                      │
│                                                             │
│  Cloud Functions (TypeScript, v2 API):                      │
│    ├── linkUsers        — Atomic pairing via batch write    │
│    ├── notifyPartner    — FCM fan-out + APNs widget push    │
│    ├── unlinkConnection — Atomic disconnect + push notify   │
│    ├── expireCodes      — Scheduled cleanup (10min TTL)     │
│    └── apnsHelper       — Direct APNs for WidgetKit tokens  │
│                                                             │
│  Firestore: users/, connections/, codes/                    │
│  All user content fields = AES-256-GCM ciphertext (Base64)  │
└─────────────────────────────────────────────────────────────┘
```

### Encryption Pipeline

1. **Pairing** — Each device generates an X25519 key pair. Public keys are exchanged via Firestore during the pairing flow.
2. **Key derivation** — Both devices independently derive a shared symmetric key using Diffie-Hellman.
3. **Storage** — The 256-bit symmetric key is stored in the Keychain with `kSecAttrSynchronizable = true`, syncing across the user's devices via iCloud Keychain.
4. **Encrypt-on-write** — Every status, message, display name, location, and heartbeat is encrypted client-side with AES-256-GCM before touching Firestore.
5. **Decrypt-on-read** — The Notification Service Extension decrypts push payloads inline using its own lightweight Keychain query (no Firebase SDK dependency).

### Push Notification Pipeline

The system is optimized for speed — partner updates should arrive in 1-2 seconds:

1. Client writes encrypted data to Firestore **and** calls `notifyPartner` Cloud Function simultaneously
2. Cloud Function reads caller's encrypted fields from Firestore and includes them in the FCM data payload
3. FCM delivers to all partner devices → **NSE intercepts** → decrypts payload → writes to App Group → reloads widgets
4. 500ms after FCM, Cloud Function sends direct APNs widget push to trigger WidgetKit reload (belt and suspenders)
5. Main app's `PushManager` also handles the push as a fallback (Firestore fetch if payload is missing)

## Project Structure

```
Fond/
├── Fond/                           # Xcode project root
│   ├── Fond/                       # iOS/iPadOS/macOS main target
│   │   ├── FondApp.swift           # App entry point + AppDelegate
│   │   ├── ContentView.swift       # Root router (auth → name → pair → connected)
│   │   ├── Views/
│   │   │   ├── SignInView.swift         # Apple + Google Sign-In
│   │   │   ├── DisplayNameView.swift    # Name setup for new users
│   │   │   ├── PairingView.swift        # Generate/enter 6-char code
│   │   │   ├── ConnectedView.swift      # Main hub — partner card + messaging
│   │   │   ├── StatusPickerSheet.swift  # Category-grouped status picker
│   │   │   ├── DailyPromptCard.swift    # Rotating daily prompts
│   │   │   ├── HistoryView.swift        # Encrypted message history
│   │   │   ├── SettingsView.swift       # Account + unlink
│   │   │   └── KeySyncView.swift        # iCloud Keychain sync wait screen
│   │   └── Shared/
│   │       ├── Constants/FondConstants.swift
│   │       ├── Crypto/
│   │       │   ├── EncryptionManager.swift    # AES-256-GCM encrypt/decrypt
│   │       │   ├── KeyExchangeManager.swift   # X25519 Diffie-Hellman
│   │       │   └── KeychainManager.swift      # iCloud Keychain CRUD
│   │       ├── Models/
│   │       │   ├── UserStatus.swift           # 16 statuses, 4 categories
│   │       │   ├── ConnectionState.swift
│   │       │   ├── DailyPrompt.swift
│   │       │   └── ...
│   │       ├── Services/
│   │       │   ├── AuthManager.swift          # @Observable, Apple/Google auth
│   │       │   ├── FirebaseManager.swift       # All Firestore operations
│   │       │   ├── PushManager.swift           # FCM + device registration
│   │       │   ├── LocationManager.swift       # One-shot capture + haversine
│   │       │   ├── DailyPromptManager.swift
│   │       │   └── WatchSyncManager.swift      # WatchConnectivity bridge
│   │       └── Theme/
│   │           ├── FondColors.swift            # Adaptive light/dark palette
│   │           └── FondTheme.swift             # Mesh gradient, glass, haptics
│   ├── FondNotificationService/    # NSE target — decrypts push payloads
│   │   └── NotificationService.swift
│   ├── watchkitapp Watch App/      # watchOS companion
│   │   ├── Views/
│   │   │   ├── WatchConnectedView.swift
│   │   │   └── WatchNotConnectedView.swift
│   │   ├── HeartbeatManager.swift
│   │   └── WatchDataStore.swift
│   └── widgets/                    # Shared widget extension (all platforms)
│       ├── widgets.swift               # 5 widget families
│       ├── FondDateWidget.swift        # Anniversary/countdown widget
│       ├── FondDistanceWidget.swift    # Location distance widget
│       ├── FondWidgetPushHandler.swift # WidgetKit push token handler
│       └── widgetsBundle.swift
├── functions/                      # Firebase Cloud Functions (TypeScript)
│   └── src/
│       ├── index.ts                # Exports all functions
│       ├── linkUsers.ts            # Atomic pairing
│       ├── notifyPartner.ts        # FCM fan-out + APNs widget push
│       ├── unlinkConnection.ts     # Atomic disconnect
│       ├── expireCodes.ts          # Scheduled code cleanup
│       └── apnsHelper.ts           # Direct APNs for widget tokens
├── firestore.rules                 # Security rules (partner-read, owner-write)
├── docs/                           # Architecture docs + decision log
└── firebase.json
```

## Technical Highlights

| Area | Implementation |
|------|---------------|
| **Encryption** | CryptoKit X25519 key exchange → AES-256-GCM. Per-message unique nonce. Keys synced via iCloud Keychain (`kSecAttrSynchronizable`). |
| **Push pipeline** | Dual-path: NSE decrypts from payload (<1ms, no network) + main app Firestore fallback. Cloud Function includes encrypted fields in FCM data payload. |
| **Widget updates** | NSE writes to App Group → `WidgetCenter.reloadAllTimelines()`. Direct APNs widget push via Cloud Function with 500ms delay to avoid race condition. |
| **Cross-platform** | `#if canImport()` guards throughout. watchOS uses static gradient (no MeshGradient). Widget uses `widgetRenderingMode` for fullColor/accented/vibrant. |
| **Rate limiting** | 5-second cooldown with circular progress ring on send button. Server-side validation in Cloud Functions. |
| **Firestore rules** | Partner-read via `partnerUid` verification. Owner-write only. History is append-only and immutable. Catch-all deny. |
| **Concurrency** | Swift `async/await` throughout. `@Observable` macro for reactive state. `Sendable` conformance on managers. |
| **Design system** | 3-tier glass hierarchy (`fondGlassInteractive`, `fondGlass`, `fondGlassPlain`), animated 3×3 `MeshGradient`, centralized haptic feedback, spring animation presets. |

## Design System

The visual language is **"warm glass, not candy"** — avoiding generic pink aesthetics in favor of an amber/lavender palette that feels inviting for all users.

- **Palette**: Warm amber primary (`#E8A838`), soft lavender secondary (`#B8A0D2`), muted rose for reactions
- **Backgrounds**: Animated `MeshGradient` (3×3 grid, 6s breathing cycle) with color-shifting center point
- **Glass tiers**: Interactive glass for buttons (press feedback), tinted glass for primary surfaces, plain glass for secondary elements
- **Typography**: System fonts with `.rounded` design for brand moments, monospaced for codes
- **Haptics**: Centralized `FondHaptics` enum with pre-allocated `UIImpactFeedbackGenerator` instances for zero-latency feedback
- **Animations**: `.fondSpring` (0.5s, 0.8 damping) for state transitions, `.fondQuick` (0.3s) for micro-interactions
- **Adaptive**: `FondColors.adaptive()` factory creates dynamic `UIColor`/`NSColor` with light/dark variants; watchOS always uses dark

## Firestore Data Model

```
users/{uid}
  ├── encryptedName: string (AES-256-GCM → Base64)
  ├── encryptedStatus: string
  ├── encryptedMessage: string
  ├── encryptedLocation: string (JSON: {lat, lon})
  ├── encryptedHeartbeat: string (JSON: {bpm})
  ├── encryptedPromptAnswer: string
  ├── publicKey: string (X25519 public key, Base64)
  ├── connectionId: string
  ├── partnerUid: string
  └── devices/{deviceId}
        ├── fcmToken: string
        ├── widgetPushToken: string
        └── platform: "ios" | "ipados" | "macos" | "watchos"

connections/{id}
  ├── user1, user2: string (UIDs)
  ├── isActive: boolean
  └── history/{entryId}  (append-only, encrypted)

codes/{code}
  ├── creatorUid: string
  ├── claimed: boolean
  └── expiresAt: timestamp (10 min TTL)
```

## Tech Stack

- **Swift 6** / SwiftUI — iOS 26, iPadOS 26, macOS Tahoe, watchOS 26
- **Firebase** — Firestore, Cloud Functions (TypeScript v2), FCM, Auth
- **CryptoKit** — X25519, AES-256-GCM
- **WidgetKit** — 5 widget families with push-driven updates
- **WatchConnectivity** — iPhone ↔ Apple Watch bidirectional sync
- **HealthKit** — Heart rate sampling on Apple Watch
- **CoreLocation** — Privacy-rounded one-shot location capture

## Build Requirements

- Xcode 26 beta or later
- iOS 26 / watchOS 26 SDK
- Firebase project with Blaze plan (Cloud Functions)
- Apple Developer account (push notifications, App Groups, Keychain sharing)

## Setup

1. Clone the repo
2. Open `Fond/Fond.xcodeproj` in Xcode
3. Add your `GoogleService-Info.plist` to the Fond target
4. Configure Firebase project and deploy Cloud Functions:
   ```bash
   cd functions && npm install && npx tsc
   firebase deploy --only functions,firestore:rules
   ```
5. Upload your APNs .p8 key to Firebase Console → Project Settings → Cloud Messaging
6. Store APNs secrets for widget push:
   ```bash
   firebase functions:secrets:set APNS_KEY_P8
   firebase functions:secrets:set APNS_KEY_ID
   firebase functions:secrets:set APNS_TEAM_ID
   ```
7. Build and run on a real device (iCloud Keychain + push notifications require physical hardware)

## Privacy Design Principles

- **Zero-knowledge backend** — Firebase never sees plaintext. All user content (status, messages, names, location, heartbeat) is encrypted client-side before any network call.
- **Location precision limiting** — Coordinates rounded to 2 decimal places (~1.1km) before encryption. City names derived locally on-device.
- **No location history** — Only the latest location is stored per user, overwritten on each update.
- **Minimal data retention** — Pairing codes auto-expire after 10 minutes. Unlink deletes connection data from both user documents.
- **Client-side key management** — Private keys never leave the device. Symmetric keys sync only through Apple's iCloud Keychain infrastructure.

## License

This project is proprietary. All rights reserved.

---

Built by [Mit Sheth](https://github.com/mit112)
