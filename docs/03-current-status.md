# Fond — Current Status

> Updated: March 5, 2026 — iOS 26 Liquid Glass UI polish pass

---

## Build Status: ✅ All Targets Pass

| Target | Status |
|---|---|
| **Fond** (iOS/iPadOS/macOS) | ✅ BUILD SUCCEEDED |
| **FondNotificationService** (NSE) | ✅ Target created, needs real-device test |
| **watchkitapp Watch App** (watchOS) | ✅ BUILD SUCCEEDED |
| **widgetsExtension** (widget) | ✅ BUILD SUCCEEDED |
| **Cloud Functions** (TypeScript) | ✅ Deployed March 4, 2026 |

---

## Phases Complete

| Phase | Status | What |
|---|---|---|
| 0: Setup | ✅ | Firebase init, folder structure, security rules, Cloud Functions |
| 1: Auth + Pairing | ✅ | Apple Sign-In, Google Sign-In (code ready), display name, code gen/enter, linking |
| 2: Encryption | ✅ | X25519 key exchange, AES-256-GCM encrypt/decrypt, Keychain with iCloud sync |
| 3: Status + Messaging | ✅ | Encrypt → write → real-time listener → decrypt, history feed |
| 4: Push Pipeline | ✅ | FCM token registration, notifyPartner Cloud Function call, App Group bridge |
| 5: Widgets | ✅ | 5 widget families (inline, circular, rectangular, small, medium), reads App Group |
| 6: Unlink | ✅ | Cloud Function call, key deletion, widget cleanup |
| 7: Polish | ✅ | Rate limiting, WidgetKit reloads, error handling, display name editing |
| 8: Widget Pipeline Fix | 🟡 | NSE target + payload decryption. Cloud Functions deployed. Needs real-device test. |
| 9: iOS 26 Glass Polish | ✅ | Interactive glass on all buttons, clear glass cards, widget StandBy optimization, watchOS glass buttons |

---

## Files Created (25 total)

### Swift (21 files)
```
FondApp.swift                           — App entry, multiplatform AppDelegate, Firebase init
ContentView.swift                       — Root router: SignIn → Name → Pair → Connected

Shared/Constants/FondConstants.swift    — All app-wide constants
Shared/Models/UserStatus.swift          — available/busy/away/sleeping enum
Shared/Models/ConnectionState.swift     — signedOut/unpaired/connected/etc
Shared/Models/FondUser.swift            — Firestore users/{uid} schema
Shared/Models/FondMessage.swift         — Firestore history/{entryId} schema
Shared/Models/DeviceRegistration.swift  — Firestore devices/{deviceId} schema
Shared/Crypto/EncryptionManager.swift   — AES-256-GCM encrypt/decrypt
Shared/Crypto/KeychainManager.swift     — Keychain CRUD with iCloud sync
Shared/Crypto/KeyExchangeManager.swift  — X25519 DH + HKDF key derivation
Shared/Services/AuthManager.swift       — Firebase Auth (Apple + Google Sign-In)
Shared/Services/FirebaseManager.swift   — All Firestore operations + Cloud Function calls
Shared/Services/PushManager.swift       — FCM token + device registration
Shared/Extensions/Date+Extensions.swift — shortTimeAgo, historyTimestamp

Views/SignInView.swift                  — Apple + Google sign-in buttons
Views/DisplayNameView.swift             — Name entry after sign-in
Views/PairingView.swift                 — Generate code / Enter code (two tabs)
Views/ConnectedView.swift               — Partner status, status picker, messaging
Views/HistoryView.swift                 — Decrypted history feed
Views/SettingsView.swift                — Name edit, disconnect, sign out
```

### Widget Extension (3 files)
```
widgets/widgets.swift                   — FondWidget + 5 family views + timeline provider
widgets/widgetsBundle.swift             — Widget bundle entry point
widgets/FondWidgetPushHandler.swift     — WidgetKit push token capture
```

### Notification Service Extension (3 files) — NEW
```
FondNotificationService/NotificationService.swift          — Intercepts push, decrypts payload, writes App Group, reloads widgets
FondNotificationService/FondNotificationService.entitlements — App Group + Keychain sharing
FondNotificationService/Info.plist                         — NSE extension point config
```

### Cloud Functions (5 files)
```
functions/src/index.ts                  — Entry point, exports all functions
functions/src/notifyPartner.ts          — Push fan-out + encrypted payload forwarding
functions/src/expireCodes.ts            — Scheduled cleanup of expired codes
functions/src/unlinkConnection.ts       — Atomic disconnect + push
functions/src/apnsHelper.ts             — Direct APNs widget push (HTTP/2 + JWT)
functions/src/linkUsers.ts              — Atomic code claim + user linking
```

### Firestore
```
firestore.rules                         — Production security rules
```

---

## What's Next

1. **Real-device test of widget pipeline** — NSE only runs on physical hardware, not Simulator. Test: partner sends status → widget updates within 1-2s with app backgrounded/force-quit.
2. **Test unlink flow** — NSE now handles unlink push (clears App Group). Verify widget shows "Not Connected" when partner unlinks.
3. **Test key sync** — Verify iCloud Keychain sync works on a second real device. KeySyncView should resolve within seconds.
4. **Device test glass effects** — Verify `fondGlassInteractive` press feedback (scale + shimmer) looks correct on real hardware. Simulator approximates but doesn't show full glass refraction.
5. **Widget tutorial in onboarding** — Guide users to add widgets after pairing.
6. **Build and test on device** — Full end-to-end run on physical iPhone + Apple Watch.

---

## Architecture Implemented

```
User A (iPhone)                          Firebase                         User B (iPhone)
─────────────────                       ─────────                       ─────────────────
Sign In (Apple/Google) ──────────────→ Auth ←──────────────── Sign In
Generate Code ───────────────────────→ codes/{code} ←──────── Enter Code
Publish Public Key ──────────────────→ users/{uid}/publicKey
                                                              ← Read Public Key
                                        DH Key Exchange
Encrypt(status) ─────────────────────→ users/{uid}/encryptedStatus
callNotifyPartner() ─────────────────→ Cloud Function ──→ FCM ──→ Push
                                                              ← Snapshot Listener
                                                              ← Decrypt(status)
                                                              ← Widget reads App Group
```
