# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Critical: iOS 26 / watchOS 26 Codebase

This app targets **iOS 26, iPadOS 26, macOS 26 (Tahoe), and watchOS 26** exclusively — no backward compatibility with iOS 18 or earlier. Always check current Apple documentation (WWDC25+) before writing SwiftUI, WidgetKit, or framework code. iOS 26 introduced Liquid Glass, new WidgetKit APIs, and significant SwiftUI changes. **Do not rely on pre-iOS 26 patterns or deprecated APIs** — when in doubt, look up the docs.

## What This Is

Fond is a couples app — two people pair via a 6-character code, exchange encryption keys, then share statuses, messages, nudges, heartbeats (Apple Watch), location/distance, and daily prompts. All user content is end-to-end encrypted (AES-256-GCM). The server never sees plaintext.

This is a **new build** (started Feb 2026) — there is no legacy code, no migration debt, no prior versions in the App Store. All code in the repo is current and intentional.

**Firebase project:** `fond-cf7f5` (us-central1)

## Build & Run Commands

### iOS App (Xcode)
```bash
# Build for simulator
xcodebuild -project Fond/Fond.xcodeproj -scheme Fond -sdk iphonesimulator -configuration Debug build

# Run tests
xcodebuild -project Fond/Fond.xcodeproj -scheme Fond -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test

# Build watch app
xcodebuild -project Fond/Fond.xcodeproj -scheme "watchkitapp Watch App" -sdk watchsimulator -configuration Debug build

# Build widget extension
xcodebuild -project Fond/Fond.xcodeproj -scheme widgetsExtension -sdk iphonesimulator -configuration Debug build
```

### Cloud Functions (TypeScript)
```bash
cd functions
npm run build          # Compile TypeScript → lib/
npm run lint           # ESLint (google style + @typescript-eslint)
npm run serve          # Build + start Firebase emulator
npm run deploy         # Deploy to Firebase (runs lint + build as predeploy)
firebase functions:log # View production logs
```

### Firebase
```bash
firebase deploy --only functions              # Deploy Cloud Functions only
firebase deploy --only firestore:rules        # Deploy security rules only
firebase deploy --only functions,firestore    # Deploy both
```

## Build Order

When orienting across sessions, this is the dependency order:

1. **Shared/** (models, crypto, services, constants, theme) — everything depends on this
2. **Fond app** (views, app delegate, ContentView state machine)
3. **FondNotificationService** (NSE — decrypts push payloads, writes to App Group)
4. **widgets** (reads App Group UserDefaults, pure display)
5. **watchkitapp Watch App** (receives data via WatchConnectivity from iOS app)
6. **functions/** (Cloud Functions — independent TypeScript codebase)

## Architecture

### Platforms & Targets
Four build targets from one Xcode project, all minimum deployment **26.0**:
- **Fond** — iOS / iPadOS / macOS (Catalyst) app
- **watchkitapp Watch App** — watchOS companion
- **widgetsExtension** — WidgetKit extension (home screen, lock screen, StandBy, watchOS Smart Stack)
- **FondNotificationService** — Notification Service Extension (NSE)

Platform-specific code uses `#if canImport()` and `#if os()` guards throughout.

### State Machine (Navigation)
`ConnectionState` enum drives the entire UI flow in `ContentView.swift`:
```
signedOut → unpaired → waitingForPartner → syncingKeys → connected
```
Each state maps to a view: `SignInView` → `PairingView` → `KeySyncView` → `ConnectedView`. Transitions animate with `.fondSpring`.

### Encryption Pipeline (Zero-Knowledge)
Three-layer system — all sensitive data encrypted client-side before touching Firestore:
1. **X25519 ECDH** (`KeyExchangeManager`) — partners derive shared secret via Diffie-Hellman, HKDF-SHA256 with salt `"Fond-v1"`
2. **AES-256-GCM** (`EncryptionManager`) — every field prefixed `encrypted*` in Firestore is nonce+ciphertext+tag, Base64-encoded
3. **Keychain** (`KeychainManager`) — private key and symmetric key stored with iCloud Keychain sync enabled, shared access group `3P89U4WZAB.com.mitsheth.Fond`

Key sync edge case: new device logs into existing paired account → keys may not be synced yet → `KeySyncView` waits for iCloud Keychain delivery before proceeding.

### Push Notification Pipeline (Dual-Path)
Optimized for speed — two parallel delivery paths:
1. **NSE fast path**: Cloud Function includes encrypted fields in FCM data payload → NSE decrypts from payload directly (~1ms), writes to App Group
2. **Main app fallback**: Firestore real-time listener fires → decrypt locally (~1-2s)

Cloud Function `notifyPartner` does FCM fan-out + direct APNs widget push (500ms delay to avoid race).

### Data Sharing via App Group
App Group (`group.com.mitsheth.Fond`) UserDefaults is the shared data bus between iOS app, widget, and NSE. The app writes decrypted partner data there; widgets read it. `WidgetCenter.shared.reloadAllTimelines()` triggers refresh after writes.

### Cloud Functions (Privileged Operations)
Four functions in `functions/src/`, all Firebase Functions v2, region `us-central1`:
- `linkUsers` — atomic batch write: claim code + create connection + update both users
- `unlinkConnection` — atomic disconnect + push notification
- `notifyPartner` — FCM fan-out + direct APNs for widget tokens
- `expireCodes` — scheduled cleanup of expired pairing codes

These exist because Firestore security rules prevent one user from writing to another's document.

### Service Layer
Singleton managers with `Sendable` conformance, accessed via `.shared`:
- `FirebaseManager` — all Firestore reads/writes, App Group writes, Cloud Function calls
- `AuthManager` (@Observable) — Firebase Auth with Apple/Google Sign-In
- `PushManager` (@Observable) — FCM token management, dual-path push handling
- `LocationManager` (@Observable) — one-shot capture, Haversine distance, reverse geocode
- `DailyPromptManager` (@Observable) — deterministic UTC-day prompt rotation from bundled JSON
- `WatchSyncManager` — WatchConnectivity bridge, routes watch actions through FirebaseManager

### Widgets (WidgetKit)
Three widgets in `FondWidgetBundle`, all reading from App Group UserDefaults:

| Widget | Families | Refresh |
|--------|----------|---------|
| **FondWidget** (status/message) | accessoryInline, accessoryCircular, accessoryRectangular, systemSmall, systemMedium | 15 min + push-triggered reload |
| **FondDateWidget** (days together / countdown) | accessoryInline, accessoryCircular, systemSmall, systemMedium | At midnight |
| **FondDistanceWidget** (miles/km apart) | accessoryInline, accessoryCircular, systemSmall | 30 min |

Rendering modes: `.fullColor` (home screen, warm Fond palette), `.accented` (system tints amber), `.vibrant` (lock screen, white on translucent). FondWidget uses `.pushHandler(FondWidgetPushHandler.self)` for direct APNs widget pushes.

**Not yet implemented:** `RelevantIntentManager` / relevance entries for watchOS Smart Stack surfacing — widgets currently rely on timeline refresh only.

### Design System (Liquid Glass)
- `FondTheme` — iOS 26 `.glassEffect()` modifiers (`.fondGlass()`, `.fondGlassInteractive()`, `.fondGlassPlain()`), `.fondCard()` with `GlassEffect.clear` fallback to surface+shadow. Animated `MeshGradient` background (3x3 grid, 6s breathing cycle; static `LinearGradient` on watchOS). Centralized haptics (`FondHaptics`), animation presets (`.fondSpring`, `.fondQuick`).
- `FondColors` — adaptive color factory with `adaptive(light:dark:)`, resolves per platform trait/appearance. watchOS always uses dark variant.

## Key Conventions

- **Never rename `UserStatus` raw values** — they're stored in Firestore. New statuses must handle unknown values gracefully via `displayInfo(forRawValue:)`.
- **Never rename `FondMessage.EntryType` raw values** — same reason, stored in history documents.
- **All encrypted Firestore fields are prefixed `encrypted*`** and contain Base64-encoded AES-256-GCM ciphertext.
- **Plaintext Firestore fields** exist only where needed for queries/ordering: `publicKey`, `connectionId`, `partnerUid`, `createdAt`, `anniversaryDate`, `countdownDate`, `timestamp`, `type`.
- **History is append-only and immutable** — Firestore rules enforce `allow update, delete: if false` on the history subcollection.
- **Constants live in `FondConstants.swift`** — collection names, App Group ID, Keychain access group, rate limits, UserDefaults keys. Reference this file for any magic strings.
- **`#if canImport()`** guards are required for Firebase SDK imports — widget and NSE targets don't link all Firebase frameworks.

## Dependencies

**SPM**: Firebase iOS SDK v12.9.0, Google Sign-In v9.1.0 (see `Package.resolved`)
**npm** (functions/): firebase-admin ^13.6.0, firebase-functions ^7.0.0, TypeScript ^5.7.3, Node 24
