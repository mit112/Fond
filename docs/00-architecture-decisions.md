# Fond — Architecture & Design Decisions

> App Name: **Fond** | Subtitle: "Your Person, At a Glance"
> Initial idea thought process — capturing every decision and the reasoning behind it.
> Date: February 2026 | Target: iOS 26, iPadOS 26, macOS Tahoe, watchOS 26

---

## 1. The Concept

**Fond** is a couples widget app. Two people pair up and can see each other's status and short messages directly on their lock screen, home screen, watch face, and Mac desktop — across every Apple device they own.

No need to open the app. It's ambient awareness of your person.

### Core Experience
1. Sign in (Apple or Google)
2. Enter your display name
3. One person generates a 6-character code, texts it to their partner
4. Partner enters the code → they're linked
5. Each person can set a status (Available, Busy, Away, Sleeping) with emoji indicators
6. Send short, widget-optimized messages (character limits tuned per widget size: 30–100 chars)
7. Partner's status + last message lives on widgets — always visible, zero friction

### What Makes It Work
The lock screen becomes a passive, always-on connection with one specific person. Glanceable. No app to open. No notification to dismiss. Just there.

---

## 2. Technical Requirements

1. **Two users need to find each other** — pairing via a 6-character code
2. **Two users need to see each other's data in near-real-time** — status + message
3. **Widgets must refresh when the partner updates** — push-triggered, not polling
4. **Works when the app is closed** — background push updates
5. **Works across all Apple devices** — iPhone, iPad, Mac, Apple Watch
6. **End-to-end encrypted** — Firebase/Google never sees plaintext content
7. **History/feed available** — couples can reflect on past statuses and messages
8. **Clean unlinking** — if the relationship ends, disconnect fully and securely
9. **Scales gracefully** — from 10 couples to 100K without breaking existing users

---

## 3. Why Firebase Over CloudKit

We evaluated four options: CloudKit (CKSyncEngine + CKShare), Firebase (Firestore + FCM), custom server + APNs, and Supabase.

### CloudKit — Rejected
**Pros:** Free, native, private (data in user's iCloud), CKSyncEngine simplifies sync.

**Critical cons:**
- **Pairing is awkward.** CKShare is designed around sharing links (AirDrop/Messages), not code-based pairing. Would need the public database for code lookup, which has no real-time push — it's poll-based.
- **Widget push gap.** iOS 26 widget push notifications require YOUR server to send pushes to APNs with widget-specific tokens. CloudKit's built-in push doesn't speak that protocol. You'd still need a server, killing the "zero infrastructure" benefit.
- **CKShare is overkill.** The sharing infrastructure (UICloudSharingController, share acceptance, participant management) is designed for document collaboration, not a persistent 1:1 connection.
- **Testing is painful.** Need two real devices with two different iCloud accounts. Simulators can't receive pushes.
- **No cross-platform path ever.** If we ever want Android, CloudKit is a dead end.

### Firebase — Chosen
**Pros:**
- **Pairing is trivial.** Write a code doc to Firestore, query for it, done.
- **Real-time listeners are native.** `addSnapshotListener` delivers changes in ~100-500ms when the app is open.
- **FCM can send widget push notifications directly.** We control the payload, can target WidgetKit push tokens specifically.
- **Cloud Functions = server logic without a server.** Push routing, code expiration, abuse prevention.
- **Cross-platform possible later.** Android, web.
- **Testing is easy.** Works on simulators, no iCloud accounts needed.

**Cons (acknowledged and acceptable):**
- Cost (minimal at our scale — see cost model below)
- Privacy perception (mitigated by E2E encryption — Firebase only sees ciphertext)
- SDK size (~10-15 MB)

### Custom Server / Supabase — Deferred
Maximum flexibility but overkill for v1. Could migrate to custom backend later if needed; Firestore data model is simple enough to port.

---

## 4. Authentication

### Decision: Required Sign-In with Apple + Google

**Flow:**
```
Launch → Sign in with Apple / Google → Enter display name → 
Generate code OR Enter partner's code → Connected
```

3 taps to connected. Sign-in is required (not anonymous) because:
- Stable, recoverable identity across devices — survives phone replacement
- Needed for reliable multi-device key sync (iCloud Keychain requires a real account)
- No anonymous-to-linked migration headaches later
- Future features may depend on authenticated identity

**Implementation:** Firebase Auth with Apple and Google providers. Both produce a stable Firebase UID. Display name comes from user input (not auth provider) — people may want a pet name.

**Note:** Apple Sign-In can hide email via relay. That's fine — we never need their email. The Firebase UID is the identity.

---

## 5. End-to-End Encryption

### Design Principle
Firebase/Google can NEVER read any user content. Status text, messages, display names — everything stored as ciphertext. The Cloud Function that triggers pushes only knows "Person A wrote something new" — it never reads or forwards encrypted content.

### Cryptographic Approach
- **Key agreement:** X25519 (Curve25519 Diffie-Hellman)
- **Symmetric encryption:** AES-256-GCM (authenticated encryption)
- **Key derivation:** HKDF from shared DH secret
- **Library:** Apple CryptoKit (native, zero dependencies)

### Key Exchange Protocol (on pairing)
```
Person A generates X25519 key pair (private + public)
Person A stores private key in Keychain (shared App Group, synchronizable)
Person A writes public key to Firestore user document (public keys are safe to share)

Person B does the same

On connection:
  Both devices fetch partner's public key from Firestore
  Both derive shared secret: X25519(myPrivate, partnerPublic)
  Shared secret → HKDF → AES-256-GCM symmetric key
  Symmetric key stored in Keychain (synchronizable via iCloud Keychain)
```

### What Gets Encrypted vs. Plaintext

| Field | Encrypted? | Why |
|---|---|---|
| Status enum | ✅ Yes | Even status patterns reveal behavior |
| Status emoji | ✅ Yes | Derived from status |
| Message text | ✅ Yes | Obviously |
| Display name | ✅ Yes | Privacy |
| Timestamps | ❌ No | Needed for ordering, low sensitivity |
| UIDs | ❌ No | Needed for queries and push routing |
| Connection metadata | ❌ No | Just IDs |
| FCM/push tokens | ❌ No | Needed by Cloud Function for push delivery |
| Public keys | ❌ No | Public by design |

### Multi-Device Key Sync via iCloud Keychain
When the symmetric key is stored with `kSecAttrSynchronizable = true`, iCloud Keychain automatically distributes it to all the user's devices using Apple's own E2E encryption. The key appears on their iPad, Mac, and Apple Watch without us building anything.

iCloud Keychain sync can take seconds to minutes for new items. If Person A pairs on iPhone, their iPad widget may show "Syncing your connection..." briefly until the key arrives. Acceptable for a one-time event.

### Key Rotation on Unlink
When two people disconnect, both devices delete the shared symmetric key. New connections generate entirely new key pairs and shared secrets. The old partner can never decrypt new messages.

### Widget Decryption
Widget extensions need to decrypt too. Two paths:
1. **App writes decrypted data** to App Group UserDefaults when it runs → widget reads plaintext
2. **Widget decrypts independently** using symmetric key from App Group Keychain → fallback when app hasn't run

Both paths must work. The symmetric key lives in the shared Keychain accessible to both the app and widget extension targets.

---

## 6. Firestore Data Model

```
users/{uid}/
  publicKey: "base64..."             // X25519 public key — plaintext (public by design)
  encryptedName: "base64..."         // AES-256-GCM ciphertext
  encryptedStatus: "base64..."       // AES-256-GCM ciphertext
  encryptedMessage: "base64..."      // AES-256-GCM ciphertext
  lastUpdatedAt: Timestamp           // plaintext — needed for ordering
  connectionId: "conn_abc"           // plaintext — needed for queries
  partnerUid: "uid_xyz"              // plaintext — needed for push routing
  createdAt: Timestamp

  devices/{deviceId}/                // subcollection — one doc per physical device
    platform: "ios" | "ipados" | "macos" | "watchos"
    fcmToken: "..."
    widgetPushToken: "..."
    lastSeen: Timestamp
    appVersion: "1.0.0"

connections/{connectionId}/
  user1: "uid_abc"
  user2: "uid_xyz"
  createdAt: Timestamp
  isActive: true

  history/{entryId}/                 // subcollection — append-only encrypted log
    authorUid: "uid_abc"
    type: "status" | "message"       // plaintext — needed for filtering
    encryptedPayload: "base64..."    // the actual content, encrypted
    timestamp: Timestamp

codes/{code}/                        // e.g., "X7K2M9" — temporary, auto-expires
  creatorUid: "uid_abc"
  createdAt: Timestamp
  expiresAt: Timestamp               // 10 minutes from creation
  claimed: false
```

### Design Rationale
- **`users/{uid}`** holds CURRENT state — single document read for widget. Gets overwritten on every update.
- **`connections/{id}/history/`** holds the LOG — every status change and message, append-only. Queried with `.order(by: "timestamp").limit(to: 50)` for pagination.
- **Denormalization is intentional.** Widget path = single doc read (fast). History = query (only when user opens feed screen). Two access patterns, two data locations.
- **`devices/` subcollection** because one user has multiple devices, each with its own push tokens. Cloud Function fans out pushes to ALL devices.

---

## 7. Push Notification Pipeline (Speed is Everything)

### Design Principle
The partner must receive the update as fast as possible. This is the main essence of the app.

### Two Update Paths

**Path 1: App is open (real-time listener)**
```
Person A updates → Firestore write → Person B's snapshot listener fires → UI updates
Latency: ~100-500ms
```

**Path 2: App is closed / widget only (push pipeline)**
```
Person A updates
  → Simultaneously:
    1. Firestore write (persistence + history)
    2. HTTPS callable Cloud Function "notifyPartner" (push)
  → Cloud Function reads partner's devices/ subcollection
  → Sends FCM push to EVERY registered device (fan-out)
  → FCM → APNs delivery
  → Widget push token → WidgetKit reloads timeline
  → Widget extension reads + decrypts → renders
Latency: ~1-2 seconds (warm function)
```

### Speed Optimizations
1. **Minimum instances on Cloud Function** — `minInstances: 1` eliminates cold starts (~1-2 second savings). Costs a few dollars/month.
2. **Direct HTTPS callable** — Client calls `notifyPartner()` directly instead of waiting for Firestore trigger propagation (saves ~500ms).
3. **FCM high priority** — `apns-priority: 10` for immediate delivery, not batched.
4. **Parallel write + push** — Firestore write and Cloud Function call happen simultaneously from the client.

### Push Fan-Out (Multi-Device)
When Person A updates, the Cloud Function:
1. Reads `users/{partnerUid}/devices/` subcollection
2. Loops through all registered devices
3. Sends FCM push to each one (typically 1-4 devices)
4. Each device's widget refreshes independently

Cost: negligible (4 FCM messages instead of 1).

---

## 8. Multi-Platform Strategy

### Platforms
- **iPhone** (iOS 26) — primary device, full app experience
- **iPad** (iPadOS 26) — same app, adapted layout
- **Mac** (macOS Tahoe) — native SwiftUI, desktop widgets + Notification Center
- **Apple Watch** (watchOS 26) — independent watch app, complications, Smart Stack

### Widget Families Per Platform

| Family | iPhone | iPad | Mac | Watch | Purpose |
|---|---|---|---|---|---|
| `accessoryInline` | ✅ | ✅ | ❌ | ✅ | "Alex is available 💚" |
| `accessoryCircular` | ✅ | ✅ | ❌ | ✅ | Status emoji + time ago |
| `accessoryRectangular` | ✅ | ✅ | ❌ | ✅ | Name + status + truncated message |
| `systemSmall` | ✅ | ✅ | ✅ | ❌ | Compact home screen view |
| `systemMedium` | ✅ | ✅ | ✅ | ❌ | Full status + message |
| Relevant widget | ❌ | ❌ | ❌ | ✅ | Smart Stack — contextual surfacing |

### watchOS 26 Specifics
- **Relevant widgets** surface in the Smart Stack when the partner's status changes — the watch raises and you see "Alex is available 💚" without installing anything on a watch face.
- **Controls** (future) — quick-toggle your own status from the watch (wrist flick → tap "Busy").
- **Independent watch app** — talks directly to Firestore, works without iPhone nearby.
- **Widget push notifications now work on watchOS 26** — previously watch complications couldn't be push-updated.

### iOS 26 Widget Specifics
- **Accented rendering (Liquid Glass)** — widgets must handle `widgetRenderingMode` for glass presentation on Home Screen.
- **Use `desaturated` or `accentedDesaturated`** for images to blend with the home screen.
- One widget extension, one codebase, all platforms. `@Environment(\.widgetFamily)` branches rendering per size.

### Codebase Structure
```
Fond/
  Shared/                      // All platforms
    Models/
    Crypto/                    // CryptoKit encryption/decryption
    Services/
      FirebaseManager.swift
      KeychainManager.swift
      EncryptionManager.swift
    
  App/                         // iOS + iPadOS + macOS (one multiplatform target)
    ContentView.swift
    SetupView.swift
    ConnectedView.swift
    HistoryView.swift
    SettingsView.swift
    
  WatchApp/                    // watchOS (separate target)
    WatchContentView.swift
    WatchConnectedView.swift
    
  WidgetExtension/             // Shared widget extension (all platforms)
    ConnectionWidget.swift
    WidgetViews.swift
    TimelineProvider.swift
    RelevanceProvider.swift    // watchOS relevant widget
```

---

## 9. Unlink: Clean Disconnection

### When Person A Unlinks

**Client-side (Person A's device):**
- Delete symmetric key from Keychain (propagates deletion via iCloud Keychain to all their devices)
- Clear App Group UserDefaults → widget immediately shows "Not Connected"
- Clear local SwiftData cache
- Reload all widget timelines

**Firestore (via Cloud Function `unlinkConnection`):**
- Set `connections/{id}.isActive = false`
- Clear Person A's user doc: `connectionId`, `partnerUid`, `encryptedStatus`, `encryptedMessage`, `encryptedName` → null
- Clear Person B's user doc: same fields → null
- Send push to ALL of Person B's devices: "Your connection has ended"

**Person B's devices (on receiving push):**
- Delete symmetric key from Keychain
- Clear App Group UserDefaults
- Clear local SwiftData cache
- Reload all widgets → "Not Connected"
- Show in-app notification if app is open

**History:**
- History subcollection is NOT deleted by default
- Both users can choose "Delete all history" separately
- History is encrypted and keys are deleted → effectively unreadable anyway
- Explicit deletion offered as an option for peace of mind

### Edge Cases
- **Person B is offline when A unlinks?** Cloud Function clears B's Firestore doc. Next time B's app or widget refreshes, they see the connection is gone.
- **Both unlink simultaneously?** Cloud Function is idempotent — running twice on an already-inactive connection is a no-op.
- **Reconnect with each other?** Yes — new code, new key exchange, new symmetric key. Clean slate.
- **Blocking?** Not in v1. Architecture supports it — add `blockedUids` array to user doc.

---

## 10. Cost Model

### Firestore Free Tier (Spark Plan)
50K reads/day, 20K writes/day, 1 GiB storage.

### Per Active Couple Per Day
- Status updates: ~5 writes (user doc) + ~5 writes (history) = **10 writes**
- Partner reads (app opens + widget refreshes): ~20 reads
- History browsing (occasional): ~10 reads
- **Total: ~10 writes, ~30 reads per couple per day**

### Scale Thresholds
| Scale | Reads/Day | Writes/Day | Monthly Cost |
|---|---|---|---|
| 100 couples | 3K | 1K | Free |
| 2,000 couples | 60K | 20K | Free (near limit) |
| 10,000 couples | 300K | 100K | ~$11/month |
| 100,000 couples | 3M | 1M | ~$110/month |

### Cloud Functions
Free tier: 2M invocations/month. At ~10 updates/couple/day × 30 days = 300 invocations/couple/month. Free tier covers ~6,600 couples. After that, $0.40/million invocations.

---

## 11. Future Feature Expansion

| Feature | Supported? | How |
|---|---|---|
| Message history / feed | ✅ Already designed | `history/` subcollection |
| Reactions to messages | ✅ Easy | Add `reactions` field to history entries |
| Photos / images | ✅ Doable | Firebase Storage + URL in history entry |
| Multiple widget themes | ✅ Trivial | Just SwiftUI, no backend change |
| Apple Watch complications | ✅ Native | Same widget extension |
| watchOS relevant widget | ✅ Designed in | `RelevanceEntriesProvider` |
| Shared calendar / events | ✅ New subcollection | `connections/{id}/events/` |
| Android partner | ✅ Firebase is cross-platform | Same Firestore + FCM |
| End-to-end encryption | ✅ Built from day 1 | CryptoKit + iCloud Keychain |
| More than 2 people (groups) | ⚠️ Schema evolution needed | `user1`/`user2` → `members: [uid]` array |
| Offline-first | ✅ Built-in | Firestore has offline persistence |

---

## 12. Final Decision Summary

| Layer | Choice | Why |
|---|---|---|
| **Auth** | Firebase Auth — Apple Sign-In + Google Sign-In (required) | Stable identity, device recovery |
| **Database** | Firestore | Real-time listeners, subcollections, scales |
| **Backend Logic** | Firebase Cloud Functions | Push routing, code expiration, no server |
| **Encryption** | CryptoKit X25519 + AES-256-GCM | Apple-native, zero dependencies |
| **Key sync (own devices)** | iCloud Keychain (kSecAttrSynchronizable) | Apple handles E2E key distribution |
| **Push to widgets** | FCM → APNs, fan-out to all partner devices | Near-real-time, all platforms |
| **Widget platforms** | iOS, iPadOS, macOS, watchOS | One extension, all platforms |
| **watchOS strategy** | Independent watch app + relevant widget | Works without iPhone |
| **Codebase** | Single Xcode project, multiplatform targets | Shared models/crypto/services |
| **Per-device registration** | `users/{uid}/devices/{deviceId}` subcollection | Each device has own push tokens |
| **Local persistence** | SwiftData (no CloudKit sync) | Caching, offline history |
| **Privacy** | E2E encryption on all user content | Firebase only sees ciphertext |

---

*This document will be updated as decisions evolve during implementation.*
