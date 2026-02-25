# Fond — Phase 0 Coding Plan

> Detailed execution plan for the first coding session.
> Every step is a concrete action — no ambiguity.

---

## Current State (Verified)

**What exists:**
- Xcode project at `/Users/mitsheth/Documents/Fond/Fond/` with 3 targets (main app, watchOS, widget extension)
- Firebase project `fond-cf7f5` (Blaze plan, us-central1) — fully configured
- `GoogleService-Info.plist` in main app target
- Firebase SDK added via SPM (FirebaseAuth, FirebaseFirestore, FirebaseMessaging) — main target only
- Entitlements on all 3 targets (App Groups, Keychain Sharing, Sign in with Apple)
- `firebase init` complete — `firestore.rules` (deny-all placeholder), `functions/src/index.ts` (empty scaffold)
- Cloud Functions scaffold: TypeScript, Node 24, firebase-admin ^13.6.0, firebase-functions ^7.0.0

**What does NOT exist yet:**
- `FirebaseApp.configure()` — not called anywhere
- No project folder structure (Shared/, Services/, Models/, Crypto/)
- Firestore security rules are deny-all placeholder
- Cloud Functions have no actual function code
- Deployment targets not confirmed at iOS 26 / watchOS 26 / macOS 26

---

## Execution Plan: 5 Steps

### Step 1: `FirebaseApp.configure()` in FondApp.swift

**What:** Add Firebase initialization to the main app entry point using a proper AppDelegate adapter pattern (best practice for Firebase + SwiftUI).

**Why AppDelegate adapter:** Firebase recommends calling `FirebaseApp.configure()` as early as possible in the app lifecycle. The `@UIApplicationDelegateAdaptor` pattern ensures it runs in `application(_:didFinishLaunchingWithOptions:)` before any SwiftUI views initialize. This is also required later for push notification registration (FCM), handling deep links, and Google Sign-In callback.

**File changes:**
```
Fond/Fond/FondApp.swift  — modify existing file
```

**Code approach:**
```swift
import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct FondApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Platform note:** `@UIApplicationDelegateAdaptor` works on iOS/iPadOS. For macOS, we'll need `@NSApplicationDelegateAdaptor`. Since this is a multiplatform target, we'll use conditional compilation (`#if os(macOS)`). The watchOS target will need its own Firebase init — but that's Phase 1 (when we register the watch app with Firebase).

**Verification:** Build on iOS simulator — app should launch without crash, Firebase console should show the app as connected.

---

### Step 2: Project Folder Structure

**What:** Create the shared code architecture. Files in `Shared/` will eventually be added to all 3 Xcode targets (main app, watchOS, widget extension). Target membership will be set in Xcode manually after file creation.

**Why this structure:** Follows the architecture doc (Section 8) — one codebase, shared models/crypto/services across all platforms. Clean separation of concerns.

**Directory structure to create:**
```
Fond/Fond/
  Shared/
    Models/
      UserStatus.swift          — Status enum (Available, Busy, Away, Sleeping)
      ConnectionState.swift     — Connection state model  
      FondUser.swift            — User model matching Firestore schema
      FondMessage.swift         — Message model for history entries
    Crypto/
      EncryptionManager.swift   — AES-256-GCM encrypt/decrypt (placeholder)
      KeychainManager.swift     — Keychain CRUD with iCloud sync (placeholder)
      KeyExchangeManager.swift  — X25519 key exchange (placeholder)
    Services/
      FirebaseManager.swift     — Firestore read/write wrapper (placeholder)
      AuthManager.swift         — Firebase Auth wrapper (placeholder)
      PushManager.swift         — FCM + widget push token management (placeholder)
    Extensions/
      Date+Extensions.swift     — Date formatting helpers
    Constants/
      FondConstants.swift       — App Group ID, Keychain group, collection names
```

**Key principle:** Every file starts as a clean, compilable placeholder with the correct imports, struct/class definition, and TODO comments for Phase 1+ implementation. No dead code, no unresolvable imports.

**What goes in each placeholder:**

- **`FondConstants.swift`** — The single source of truth for all string constants:
  ```swift
  enum FondConstants {
      static let appGroupID = "group.com.mitsheth.Fond"
      static let keychainGroup = "com.mitsheth.Fond"
      
      // Firestore collections
      static let usersCollection = "users"
      static let connectionsCollection = "connections"
      static let codesCollection = "codes"
      static let devicesSubcollection = "devices"
      static let historySubcollection = "history"
      
      // Limits
      static let codeLength = 6
      static let codeExpirationMinutes = 10
      static let maxMessageLength = 100
      static let rateLimitSeconds = 5
  }
  ```

- **`UserStatus.swift`** — The core status enum:
  ```swift
  enum UserStatus: String, Codable, CaseIterable {
      case available, busy, away, sleeping
      
      var emoji: String { ... }
      var displayName: String { ... }
  }
  ```

- **`FondUser.swift`** — Matches the Firestore `users/{uid}` schema exactly:
  ```swift
  struct FondUser: Codable, Identifiable {
      var id: String  // Firebase UID
      var publicKey: String?
      var encryptedName: String?
      var encryptedStatus: String?
      var encryptedMessage: String?
      var lastUpdatedAt: Date?
      var connectionId: String?
      var partnerUid: String?
      var createdAt: Date?
  }
  ```

**Target membership plan:**
- `Shared/` → all 3 targets (main app, watchOS, widgets)
- `Services/AuthManager.swift` → main app + watchOS only (widget doesn't auth)
- `Services/PushManager.swift` → main app + watchOS only
- Everything else in Shared → all 3 targets

**Note:** Creating files on disk is done programmatically. Adding them to Xcode targets requires either `xcodeproj` manipulation via Ruby gem, or manual drag-and-drop in Xcode. We'll create the files and then provide clear instructions for target membership setup.

---

### Step 3: Firestore Security Rules

**What:** Replace the deny-all placeholder with production-ready security rules that enforce the data model from the architecture doc.

**File:** `firestore.rules` (at project root `/Users/mitsheth/Documents/Fond/firestore.rules`)

**Rule design (from architecture doc Section 6 + open questions):**

1. **`users/{uid}`** 
   - Read: Owner OR their verified partner (partner's `connectionId` matches)
   - Write: Owner only, to their own doc
   - Subcollection `devices/{deviceId}`: Owner only (read + write)

2. **`codes/{code}`**
   - Create: Any authenticated user (to generate a pairing code)
   - Read: Any authenticated user (to look up a code when entering it)
   - Update: Any authenticated user can set `claimed: true` (only if currently `false`)
   - Delete: Nobody (handled by Cloud Function cleanup)

3. **`connections/{connectionId}`**
   - Read: Only the two users in the connection (`user1` or `user2`)
   - Create: Any authenticated user (on pairing)
   - Update: Only the two users in the connection
   - Delete: Nobody (Cloud Function handles unlink)
   - Subcollection `history/{entryId}`:
     - Read: Only the two connected users
     - Create: Only the two connected users (append-only)
     - Update/Delete: Nobody (immutable history)

**Key security patterns:**
- `request.auth != null` — must be signed in
- `request.auth.uid == uid` — can only write own doc
- Partner verification via `get(/databases/$(database)/documents/users/$(request.auth.uid)).data.partnerUid`
- Connection membership via `resource.data.user1 == request.auth.uid || resource.data.user2 == request.auth.uid`

**Important considerations:**
- Rules should be tight but not over-engineered for v1
- `exists()` and `get()` count as Firestore reads (billed) — use sparingly
- We validate data types on writes to prevent schema corruption
- Timestamp validation prevents future-dating

---

### Step 4: Cloud Functions

**What:** Write the initial Cloud Functions in TypeScript using the **v2 API** (which is what firebase-functions ^7.0.0 uses).

**Files:**
```
functions/src/
  index.ts              — Main entry point, re-exports all functions
  notifyPartner.ts      — HTTPS Callable: send push to partner's devices
  expireCodes.ts        — Scheduled: clean up expired pairing codes
  unlinkConnection.ts   — HTTPS Callable: disconnect two users
```

**Function details:**

#### 4a. `notifyPartner` (HTTPS Callable — onCall v2)
This is the **most critical function** — it's in the hot path of every status/message update.

```typescript
// v2 API pattern:
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

export const notifyPartner = onCall(
  { 
    region: "us-central1",
    minInstances: 1,  // Eliminates cold starts (~$3/month)
  },
  async (request) => {
    // 1. Verify auth
    if (!request.auth) throw new HttpsError("unauthenticated", "...");
    
    // 2. Look up partner UID from caller's user doc
    // 3. Read partner's devices/ subcollection
    // 4. Fan-out FCM to ALL partner devices
    //    - Widget push tokens → silent push with widget reload
    //    - FCM tokens → notification (for messages) or silent (for status)
    // 5. Return success
  }
);
```

**Key design decisions:**
- Uses `onCall` (v2) — NOT `onRequest`. `onCall` automatically validates Firebase Auth tokens.
- `minInstances: 1` — keeps one container warm. Critical for speed. Cost: ~$3/month.
- Region locked to `us-central1` to match Firestore location.
- Function does NOT read or decrypt content. Privacy preserved.

#### 4b. `expireCodes` (Scheduled Function)
```typescript
import { onSchedule } from "firebase-functions/v2/scheduler";

export const expireCodes = onSchedule(
  { schedule: "every 5 minutes", region: "us-central1" },
  async (event) => {
    // Query codes/ where expiresAt < now AND claimed == false
    // Delete expired codes in batch
  }
);
```

#### 4c. `unlinkConnection` (HTTPS Callable)
```typescript
export const unlinkConnection = onCall(
  { region: "us-central1" },
  async (request) => {
    // 1. Verify auth
    // 2. Read caller's user doc → connectionId + partnerUid
    // 3. Batch write: deactivate connection, clear both user docs
    // 4. Send push to partner's devices
    // 5. Return success
  }
);
```

**Deployment note:** Functions will NOT be deployed yet — just written and verified to compile (`npm run build`). Deployment happens when pairing is ready to test (Phase 1).

---

### Step 5: Verify Build

**Checks:**
1. `npm run build` in `/functions/` — TypeScript compiles to JS without errors
2. Xcode build on iOS simulator — main app launches, Firebase initializes
3. No warnings from Firebase SDK
4. Widget extension builds
5. watchOS target builds

---

## What This Phase Does NOT Include

Explicitly deferred to later phases:
- ❌ Any UI beyond placeholder ContentView
- ❌ Auth flow (Apple/Google Sign-In) — Phase 1
- ❌ Encryption implementation — Phase 2
- ❌ Firestore read/write from Swift — Phase 3
- ❌ Push notification registration — Phase 4
- ❌ Widget views — Phase 5
- ❌ Cloud Functions deployment — Phase 1

---

## Execution Order

```
Step 1: FirebaseApp.configure()      (independent)
Step 2: Folder structure + files     (independent)
Step 3: Firestore security rules     (independent)
Step 4: Cloud Functions              (independent)
Step 5: Verify build                 (depends on all above)
```

Steps 1-4 are independent. Step 5 is final verification.

**Estimated scope:** ~15-20 files created/modified. All production-quality.

---

*Ready to execute. Say "go" to start with Step 1.*
