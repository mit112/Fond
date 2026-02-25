# Fond — Current Status

> Updated: February 24, 2026 — End of Phase 7

---

## Build Status: ✅ All Targets Pass

| Target | Status |
|---|---|
| **Fond** (iOS/iPadOS/macOS) | ✅ BUILD SUCCEEDED |
| **watchkitapp Watch App** (watchOS) | ✅ BUILD SUCCEEDED |
| **widgetsExtension** (widget) | ✅ BUILD SUCCEEDED |
| **Cloud Functions** (TypeScript) | ✅ Compiled, 0 errors |

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

### Widget Extension (2 files)
```
widgets/widgets.swift                   — FondWidget + 5 family views + timeline provider
widgets/widgetsBundle.swift             — Widget bundle entry point
```

### Cloud Functions (4 files)
```
functions/src/index.ts                  — Entry point, exports all functions
functions/src/notifyPartner.ts          — Push fan-out to partner devices
functions/src/expireCodes.ts            — Scheduled cleanup of expired codes
functions/src/unlinkConnection.ts       — Atomic disconnect + push
```

### Firestore
```
firestore.rules                         — Production security rules
```

---

## Manual Steps Still Needed Before Testing

1. **Add SPM packages** to Fond target: `FirebaseMessaging`, `FirebaseFunctions`, `GoogleSignIn-iOS`
2. **Add Google URL scheme**: Fond target → Info → URL Types → REVERSED_CLIENT_ID
3. **Create APNs Key** (.p8) → upload to Firebase Console
4. **Deploy Cloud Functions**: `cd /Users/mitsheth/Documents/Fond/functions && firebase deploy --only functions`
5. **Deploy Firestore rules**: `cd /Users/mitsheth/Documents/Fond && firebase deploy --only firestore:rules`
6. **Add new View files to Fond target** in Xcode (Views/ folder)

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
