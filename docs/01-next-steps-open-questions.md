# Fond — Next Steps & Open Questions

> Updated: February 24, 2026 — Post design system implementation

---

## Where We Left Off (Feb 24, 2026)

### First End-to-End Pairing Test Successful

Two devices (iPhone + Simulator) signed in, paired via 6-character code, and exchanged encrypted status/messages in real-time. Core flow works.

### Design System Implemented (Feb 24, 2026)

Full visual redesign across all views. See `docs/02-design-direction.md` for design reference.

**New files created:**
- `Shared/Theme/FondColors.swift` — Adaptive light/dark color palette (amber/lavender/rose accents, warm backgrounds, status colors, chat bubble colors, mesh gradient colors). watchOS uses dark values directly (no dynamic provider).
- `Shared/Theme/FondTheme.swift` — Animated `FondMeshGradient` (3×3 grid, 6s cycle, watchOS gets static `LinearGradient`), `.fondBackground()` / `.fondCard()` / `.fondGlass()` / `.fondGlassPlain()` modifiers, `FondHaptics` (iOS + watchOS), `.fondSpring` / `.fondQuick` animation presets.

**All views redesigned:**
- `ContentView` — Spring transitions between states, warm loading screen with breathing heart
- `SignInView` — Mesh gradient background, glass-styled sign-in buttons
- `DisplayNameView` — Mesh gradient, glass input field + continue button, numericText char count
- `PairingView` — Custom glass segmented control, code display on fondCard, character-slot entry with scale-up animation + auto-submit at 6 chars
- `ConnectedView` — Single-screen hub (no NavigationStack/tab bar). Mesh gradient bg, glass partner card with breathing animation, glass status picker pills, glass send button with circular cooldown ring, emoji bounce on partner status change, haptics throughout
- `HistoryView` — Day-grouped chat bubbles (amber mine, lavender partner), status changes as compact pills, auto-scroll to bottom
- `SettingsView` — Glass-styled list with warm background, SF Symbol icons, haptics on unlink/name save
- `widgets.swift` — `widgetRenderingMode` support (fullColor/accented/vibrant), warm Fond colors, `FondColors.background` container background
- `AccentColor.colorset` — Updated to warm amber (#E8A838 light / #F0B84A dark)

### Widget Push Tokens Wired Up (Feb 24, 2026)

Widget push tokens are now fully implemented across all three layers:

1. **Widget Extension** — `FondWidgetPushHandler` captures WidgetKit push token via `WidgetPushHandler` protocol, writes hex-encoded token to App Group UserDefaults. Widget config has `.pushHandler()` modifier. Push Notifications entitlement added to widget extension.

2. **Main App** — `PushManager.registerDevice()` now reads widget push token from App Group and includes it in the Firestore device document alongside the FCM token. `FirebaseManager.writePartnerDataToAppGroup()` and `clearAppGroup()` both call `WidgetCenter.shared.reloadAllTimelines()`. `PushManager.handlePushData()` also triggers widget reload on incoming pushes.

3. **Cloud Functions** — New `apnsHelper.ts` sends widget pushes directly to APNs (FCM can't do this — widget tokens are raw APNs tokens requiring `apns-push-type: widgets`). Uses Node.js built-in `crypto` (JWT signing) and `http2` modules. Both `notifyPartner` and `unlinkConnection` now send widget pushes after FCM pushes. APNs .p8 key stored as Firebase secrets.

Files created: `widgets/FondWidgetPushHandler.swift`, `functions/src/apnsHelper.ts`
Files modified: `widgets/widgets.swift`, `FondConstants.swift`, `PushManager.swift`, `FirebaseManager.swift`, `notifyPartner.ts`, `unlinkConnection.ts`, `widgetsExtension.entitlements`

**Manual steps required:**
- In Xcode: Add `FondWidgetPushHandler.swift` to the widgets extension target
- In Xcode: Add Push Notifications capability to the widgets extension target (Signing & Capabilities)
- Firebase CLI: `firebase functions:secrets:set APNS_KEY_P8` (paste .p8 key contents)
- Firebase CLI: `firebase functions:secrets:set APNS_KEY_ID` (your Key ID)
- Firebase CLI: `firebase functions:secrets:set APNS_TEAM_ID` (3P89U4WZAB)
- Deploy: `firebase deploy --only functions`

---

### watchOS UI Implemented (Feb 24, 2026)

watchOS companion app now has full read-only partner display via WatchConnectivity:

1. **iPhone side** — `WatchSyncManager.swift` (new): Sends partner data to watch via `WCSession.updateApplicationContext` whenever Firestore listener fires. Also sends disconnect state on unlink. Activated in `AppDelegate.didFinishLaunching`. `ConnectedView` now calls `syncPartnerData()` alongside the App Group write.

2. **watchOS side** — 4 new files:
   - `WatchDataStore.swift`: `@Observable` + `WCSessionDelegate`. Receives partner data from iPhone, persists to local UserDefaults, drives SwiftUI views.
   - `ContentView.swift`: Router — shows `WatchConnectedView` or `WatchNotConnectedView` based on connection state.
   - `WatchConnectedView.swift`: Warm gradient background, large status emoji, partner name (title2 bold), status label with color, message, timestamp. Emoji bounce + haptic on status change.
   - `WatchNotConnectedView.swift`: `heart.slash` icon + "Open Fond on iPhone" prompt.

3. **Architecture decision**: App Groups don't share between iPhone and Apple Watch (separate devices). WatchConnectivity `applicationContext` is the right bridge — lightweight, only latest state kept, native Apple solution.

**Manual Xcode steps required:**
- Add shared files to watchOS target (see Manual Steps section)
- Add `WatchSyncManager.swift` to Fond (iOS) target

---

### What Was Fixed Earlier This Session

1. **`linkUsers` moved to Cloud Function** — The original client-side batch write failed because the claimer can't write to the creator's user doc (Firestore rules correctly enforce `isOwner`). Created `functions/src/linkUsers.ts` — Cloud Function handles atomic batch with admin SDK.

2. **`FirebaseFunctions` SPM package was missing** — The `#if canImport(FirebaseFunctions)` guard silently skipped all Cloud Function calls. Added to Fond target in Xcode.

3. **`FirebaseMessaging` SPM package added** — Needed for push notifications.

4. **`FirebaseInAppMessaging-Beta` removed** — Was generating 403 errors, not needed.

5. **Name change now syncs to partner** — `SettingsView.saveName()` now writes encrypted name to Firestore (via new `FirebaseManager.updateEncryptedName()`), not just Firebase Auth profile.

6. **Google Sign-In now shows name prompt** — `ContentView` always shows `DisplayNameView` for new users (Google accounts auto-have a name, so it was being skipped). Returning connected users skip it.

7. **Rate limit error UX improved** — Shows a countdown timer ("Please wait 3s...") in grey instead of a sticky red error message.

### Deployed to Firebase
- All Firestore rules ✅
- All 4 Cloud Functions: `notifyPartner`, `expireCodes`, `unlinkConnection`, `linkUsers` ✅

---

## Manual Steps Status

### Done ✅
1. **SPM packages added**: FirebaseFunctions, FirebaseMessaging, GoogleSignIn-iOS
2. **FirebaseInAppMessaging-Beta removed** (was causing 403 errors)
3. **Google Sign-In URL scheme added**: `com.googleusercontent.apps.599783612554-43ivhgd5mhfulc1qtbtpstrhjgbfar25`
4. **Firestore rules deployed**
5. **Cloud Functions deployed** (all 4: notifyPartner, expireCodes, unlinkConnection, linkUsers)

### Still Needed
1. ~~**APNs .p8 key** → upload to Firebase Console~~ ✅ Done
2. **Verify Firestore composite indexes** — `expireCodes` may need one; Firebase logs a creation link on first failure
3. **watchOS target membership (Xcode)** — Ensure shared files are in the "watchkitapp Watch App" target:
   - `Shared/Models/*` (UserStatus, ConnectionState, FondUser, FondMessage, DeviceRegistration)
   - `Shared/Constants/FondConstants.swift`
   - `Shared/Extensions/Date+Extensions.swift`
   - `Shared/Theme/FondColors.swift`
   - `Shared/Theme/FondTheme.swift`
   - `Shared/Crypto/*` (EncryptionManager, KeychainManager, KeyExchangeManager)
   - Do NOT add: `AuthManager`, `FirebaseManager`, `PushManager`, `WatchSyncManager`, `Views/*`
4. **Add `WatchSyncManager.swift` to Fond (iOS) target in Xcode** — It's in Shared/Services/ but only for iOS (has `#if os(iOS)` guard)

---

## Next Work Priorities

1. ~~**APNs .p8 key upload**~~ ✅ Done
2. ~~**Widget push tokens**~~ ✅ Done
3. ~~**Liquid Glass + Design System**~~ ✅ Done — FondColors, FondTheme, mesh gradient, glass modifiers, haptics, all views redesigned. See docs/02-design-direction.md.
4. ~~**watchOS UI**~~ ✅ Done — WatchConnectivity bridge + read-only connected view. See below.
5. ~~**Expanded Status Vocabulary (Phase 1a)**~~ ✅ Done — 16 statuses across 4 categories (Availability, Mood, Activity, Love). Category-based grid picker sheet. Backward-compatible: unknown raw values degrade gracefully via `UserStatus.displayInfo()`. Watch + widget + history all handle new statuses.
6. ~~**Days-Together Counter + Countdown Widget (Phase 1b)**~~ ✅ Done — FondDateWidget with 3 families (accessoryInline, accessoryCircular, systemSmall). Anniversary + countdown date pickers in Settings. Pure client-side date math, refreshes at midnight.
7. ~~**Watch Interactivity: Nudge + Heartbeat (Phase 2)**~~ ✅ Done — Bidirectional WatchConnectivity pipeline. Watch sends nudge/heartbeat via sendMessage (real-time) with transferUserInfo fallback. iPhone-side WatchSyncManager routes actions through FirebaseManager → encrypted Firestore write → notifyPartner push. HealthKit integration for heart rate snapshots. Heartbeat pill in partner card (auto-hides after 30min). HistoryView renders nudge/heartbeat as compact pills. Cloud Function updated with new valid types + alert routing.
8. ~~**Test key sync**~~ ✅ Handled — KeySyncView now shows when keys aren't available.
9. **Test unlink flow** — Disconnect on one device, verify partner gets notified + cleaned up
10. **StandBy mode optimization (Phase 1c)** — Test existing widgets in StandBy, adjust font sizes for nightstand readability
11. ~~**Distance Widget (Phase 3a)**~~ ✅ Done — LocationManager captures one-shot location, rounds to 2 decimal places (~1.1km), encrypts, writes to Firestore. Partner listener decrypts, computes haversine distance, reverse geocodes city name, writes to App Group. FondDistanceWidget with 3 families (accessoryInline, accessoryCircular, systemSmall). Distance pill shown below partner card in ConnectedView. Locale-aware units (mi/km). Privacy: coordinates encrypted, no location history, city derived locally.
12. ~~**Daily Prompt (Phase 3b)**~~ ✅ Done — 50 bundled prompts in DailyPrompts.json, deterministic UTC-day rotation (both partners see same prompt). DailyPromptManager loads JSON, computes today's prompt, manages answer state. DailyPromptCard in ConnectedView: input → encrypt → Firestore → push → partner reveal. Both-answer reveal mechanic (wait for partner, then show side-by-side). HistoryView renders prompt answers with "💬 Daily Prompt" label. App Group + WatchConnectivity sync for prompt data.
13. **Widget tutorial in onboarding** — Guide user to add widget after pairing success
14. **Build & QA on device** — Visual QA on real iPhone + Apple Watch. Deploy updated Cloud Function first.

---

## What's Built (File Inventory)

### Swift — 27 files in Fond/Fond/
```
FondApp.swift                           — App entry, multiplatform AppDelegate, Firebase init
ContentView.swift                       — Root router with .fondSpring transitions, warm loading screen with breathing heart

Shared/Constants/FondConstants.swift    — All app-wide constants
Shared/Models/UserStatus.swift          — available/busy/away/sleeping enum
Shared/Models/ConnectionState.swift     — signedOut/unpaired/connected/syncingKeys/waitingForPartner
Shared/Models/FondUser.swift            — Firestore users/{uid} schema
Shared/Models/FondMessage.swift         — Firestore history/{entryId} schema
Shared/Models/DeviceRegistration.swift  — Firestore devices/{deviceId} schema
Shared/Crypto/EncryptionManager.swift   — AES-256-GCM encrypt/decrypt via CryptoKit
Shared/Crypto/KeychainManager.swift     — Keychain CRUD with iCloud sync + App Group
Shared/Crypto/KeyExchangeManager.swift  — X25519 DH + HKDF key derivation
Shared/Services/AuthManager.swift       — Firebase Auth (Apple + Google), @Observable
Shared/Services/FirebaseManager.swift   — All Firestore ops + Cloud Function calls + App Group bridge
Shared/Services/PushManager.swift       — FCM token + device registration + push handling
Shared/Services/WatchSyncManager.swift  — WatchConnectivity bridge: sends partner data from iPhone → Watch (iOS only)
Shared/Extensions/Date+Extensions.swift — shortTimeAgo, historyTimestamp
Shared/Theme/FondColors.swift          — Adaptive light/dark color palette, status colors, mesh gradient colors
Shared/Theme/FondTheme.swift           — Animated mesh gradient, card/glass modifiers, haptics, spring presets

Views/SignInView.swift                  — Mesh gradient bg, glass sign-in buttons
Views/DisplayNameView.swift             — Mesh gradient bg, glass input + continue button, char count
Views/PairingView.swift                 — Glass segmented control, code card, character-slot entry with auto-submit
Views/ConnectedView.swift               — Hub: mesh gradient, glass partner card, glass status picker, glass message input, real-time listener
Views/HistoryView.swift                 — Warm bubble history: amber mine, lavender partner, day separators, auto-scroll
Views/KeySyncView.swift                 — Encryption key sync wait screen (new device login). Polls Keychain every 3s, re-derives when keys arrive.
Views/SettingsView.swift                — Glass-styled list, warm bg, haptics on unlink/name save, anniversary + countdown date pickers
Views/StatusPickerSheet.swift           — Category-based grid picker for 16 statuses. Half-sheet, 4-column grid, section headers, one-tap select+dismiss.
Views/DailyPromptCard.swift             — Compact daily prompt card: input → encrypt → submit. Both-answer reveal. Collapsible, glass-styled.

Shared/Models/DailyPrompt.swift         — Prompt data model (id, text, category)
Shared/Services/LocationManager.swift   — CLLocationManager one-shot wrapper. Rounds to 2dp, encrypts, haversine, reverse geocode.
Shared/Services/DailyPromptManager.swift — Loads bundled JSON, deterministic UTC-day rotation, manages answer state.
Resources/DailyPrompts.json             — 50 bundled daily prompts across 5 categories
```

### watchOS App — 5 files in Fond/watchkitapp Watch App/
```
watchkitappApp.swift            — App entry, WCSession activation via .task
ContentView.swift               — Root router (connected vs not-connected)
WatchDataStore.swift            — @Observable + WCSessionDelegate. Bidirectional: receives partner data, sends nudge/heartbeat to iPhone. Rate limiting, send state, queued fallback.
HeartbeatManager.swift          — HealthKit heart rate query wrapper. Lazy auth, 10-min sample window, @Observable state.
Views/WatchConnectedView.swift  — Partner display + nudge button + heartbeat button. Emoji bounce, haptics.
Views/WatchNotConnectedView.swift — "Open Fond on iPhone" prompt.
```

### Widget Extension — 5 files in Fond/widgets/
```
widgets.swift              — FondWidget with 5 families + FondTimelineProvider (reads App Group)
FondDateWidget.swift       — FondDateWidget with 3 families (accessoryInline, accessoryCircular, systemSmall). Days-together counter + countdown.
FondDistanceWidget.swift   — FondDistanceWidget with 3 families (accessoryInline, accessoryCircular, systemSmall). Distance display.
widgetsBundle.swift         — Widget bundle entry point (FondWidget + FondDateWidget + FondDistanceWidget)
FondWidgetPushHandler.swift — Captures APNs widget push token → App Group UserDefaults
```

### Cloud Functions — 6 files in functions/src/
```
index.ts              — Entry point, initializeApp(), re-exports (v2 API)
notifyPartner.ts      — onCall: push fan-out to partner devices + widget APNs push (minInstances: 1)
expireCodes.ts        — onSchedule: delete expired pairing codes every 5 min
unlinkConnection.ts   — onCall: atomic batch disconnect + push + widget push to partner
linkUsers.ts          — onCall: claim code + create connection + update both users atomically
apnsHelper.ts         — Direct APNs HTTP/2 widget push (JWT signing, fan-out)
```

### Firestore
```
firestore.rules — Production security rules (users, codes, connections, history)
```

---

## Target Membership Map

| File/Folder | Fond (iOS/Mac) | watchOS | Widget |
|---|---|---|---|
| `Shared/Models/` | ✅ | ✅ | ✅ |
| `Shared/Constants/` | ✅ | ✅ | ✅ |
| `Shared/Extensions/` | ✅ | ✅ | ✅ |
| `Shared/Theme/FondColors.swift` | ✅ | ✅ | ✅ |
| `Shared/Theme/FondTheme.swift` | ✅ | ✅ | ❌ |
| `Shared/Crypto/` | ✅ | ✅ | ✅ |
| `Shared/Services/AuthManager.swift` | ✅ | ❌ | ❌ |
| `Shared/Services/FirebaseManager.swift` | ✅ | ❌ | ❌ |
| `Shared/Services/PushManager.swift` | ✅ | ❌ | ❌ |
| `Shared/Services/WatchSyncManager.swift` | ✅ | ❌ | ❌ |
| `Shared/Services/LocationManager.swift` | ✅ | ❌ | ❌ |
| `Shared/Services/DailyPromptManager.swift` | ✅ | ❌ | ❌ |
| `Shared/Models/DailyPrompt.swift` | ✅ | ✅ | ✅ |
| `Resources/DailyPrompts.json` | ✅ | ❌ | ❌ |
| `Views/*` | ✅ | ❌ | ❌ |
| `watchkitapp Watch App/*` | ❌ | ✅ | ❌ |
| `watchkitapp Watch App/HeartbeatManager.swift` | ❌ | ✅ | ❌ |
| `widgets/*` | ❌ | ❌ | ✅ |
| `widgets/FondDateWidget.swift` | ❌ | ❌ | ✅ |
| `widgets/FondDistanceWidget.swift` | ❌ | ❌ | ✅ |

Services use `#if canImport(FirebaseAuth)` / `#if canImport(FirebaseFirestore)` guards so they compile safely if accidentally included in wrong targets.

---

## Known Limitations / Future Work

### Not Yet Implemented
- ~~**watchOS app UI**~~ ✅ Done — Read-only connected view via WatchConnectivity. iPhone sends partner data to watch via `updateApplicationContext`. Watch displays partner status/name/message with warm gradient background, emoji bounce on status change, haptics. "Not Connected" prompt when unpaired. Future: quick status change from watch, Firebase auth on watchOS for independent operation.
- ~~**Widget push tokens**~~ ✅ Done — WidgetPushHandler captures tokens, PushManager registers in Firestore, Cloud Functions send direct APNs widget pushes.
- ~~**APNs key upload**~~ ✅ Done — .p8 key uploaded to Firebase Console.
- **Firestore indexes** — May need composite index for `codes` collection query. Firebase logs a creation link on first failure.
- ~~**Accented rendering (Liquid Glass)**~~ ✅ Done — Widgets use `widgetRenderingMode` for fullColor/accented/vibrant. App uses `.fondGlass()` modifiers throughout.
- **watchOS RelevanceEntriesProvider** — Mentioned in architecture doc but not implemented in widget extension.

### Edge Cases to Test
- ~~What happens when encryption key hasn't synced via iCloud Keychain to a new device?~~ ✅ Handled — ContentView now routes to KeySyncView (warm UI with polling) instead of showing a broken ConnectedView. Polls every 3s, tries both paths (symmetric key direct sync, or private key → re-derive). Shows manual retry after 30s.
- Offline pairing (Firestore offline cache should handle reads but code creation needs network)
- Both users unlink simultaneously (Cloud Function is idempotent — should be fine)
- Token refresh mid-session (MessagingDelegate handles this)
- Code expiration while user is on the Enter Code screen

---

## Key Technical Decisions Made During Implementation

1. **`@Observable` over `ObservableObject`** — AuthManager uses `@Observable` (iOS 17+). Since we target iOS 26, this is cleaner than `@Published` + `ObservableObject`.

2. **`#if canImport()` pattern** — All Firebase imports are guarded. This allows the same source files to compile across targets that may not have all Firebase SDKs linked. Widget/watch targets use stub fallbacks.

3. **Fire-and-forget Cloud Function calls** — `callNotifyPartner()` runs in parallel with Firestore writes (not awaited). Speed > guaranteed delivery. Firestore listener is the reliability fallback.

4. **App Group bridge for widgets** — App decrypts partner data → writes plaintext to App Group UserDefaults → widget reads plaintext. Widget never needs encryption keys or Firebase SDK.

5. **Linking via Cloud Function, not client-side batch** — `linkUsers` must run server-side because the claimer needs to write to the creator's user doc (which Firestore rules correctly forbid). The Cloud Function uses admin SDK to bypass rules and does atomic batch: claim code + create connection + update both users. Also adds server-side validation (already connected, expired code, self-pair). Unlinking similarly uses a Cloud Function (`unlinkConnection`).

6. **Rate limiting client-side** — 5-second cooldown in ConnectedView. Server-side rate limiting exists in the architecture doc but is not yet enforced in Cloud Functions (future work).

7. **No SwiftData** — Using Firestore offline cache only for v1. SwiftData deferred per architecture doc.

8. **WatchConnectivity for watchOS data, not Firebase SDK** — App Groups don't share data between iPhone and Apple Watch (separate devices). Rather than adding Firebase SDK to the watchOS target (complex: needs auth, GoogleService-Info.plist, etc.), we use WatchConnectivity's `updateApplicationContext` to bridge partner data from iPhone → Watch. This keeps the watch app lightweight and dependency-free. The iPhone's Firestore listener sends partner data to the watch whenever it changes. Watch stores locally in UserDefaults and displays via @Observable `WatchDataStore`. Future v2 could add Firebase to watchOS for independent operation.

9. **Bidirectional WatchConnectivity with fallback** — Watch → iPhone actions (nudge, heartbeat) use `sendMessage()` when iPhone is reachable (real-time), with `transferUserInfo()` as a queued fallback. sendMessage is instant but requires reachability; transferUserInfo is guaranteed-delivery but may be delayed. We try real-time first, catch the error, and fall back. WatchSyncManager on iPhone handles both `didReceiveMessage` and `didReceiveUserInfo` delegates, then routes through FirebaseManager into the standard encrypted-write + push pipeline. This means the watch never talks to Firebase directly — all actions are proxied through the iPhone.

10. **HealthKit lazy authorization** — HeartbeatManager requests HealthKit permission only when the user first taps "Send Heartbeat", not on app launch. This avoids premature permission prompts (App Review red flag) and means users who never use the feature never see the prompt. Read-only access to heart rate type. No health data is ever written.
