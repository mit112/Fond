# Fond — Widget Update Pipeline Fix Plan

> **Goal:** Partner sends a status/message → widget updates within 1-2 seconds, even when the app is backgrounded, suspended, or terminated.
> **Date:** March 4, 2026

---

## Status (March 4, 2026)

- [x] **Phase 1:** Cloud Function — deployed. `notifyPartner` now includes encrypted fields in FCM payload, all pushes are alert+mutable-content, widget push delayed 500ms. `unlinkConnection` also updated.
- [x] **Phase 2:** NSE code written — `FondNotificationService/NotificationService.swift`, entitlements, Info.plist created. **Needs Xcode target setup (see below).**
- [x] **Phase 3:** PushManager updated — tries payload-first decryption, falls back to Firestore.
- [x] **Phase 4:** Silent→alert conversion done in Phase 1 (all types now alert+mutable-content).
- [ ] **Phase 5:** Testing on real devices.

### Xcode Manual Steps Required

1. **Create NSE target:** File → New → Target → Notification Service Extension
   - Product Name: `FondNotificationService`
   - Team: 3P89U4WZAB
   - Bundle ID will auto-set to `com.mitsheth.Fond.FondNotificationService`
   - Language: Swift
   - **When Xcode creates the target, it will generate its own `NotificationService.swift` — DELETE the Xcode-generated file and use our existing one from `FondNotificationService/`**

2. **Point the target at our files:** In the new target's Build Settings:
   - Set the Info.plist to `FondNotificationService/Info.plist`
   - Set Code Signing Entitlements to `FondNotificationService/FondNotificationService.entitlements`
   - Or: just drag our 3 files into the Xcode-created group and delete its auto-generated ones

3. **Add capabilities to NSE target** (Signing & Capabilities tab):
   - App Groups → `group.com.mitsheth.Fond`
   - Keychain Sharing → `$(AppIdentifierPrefix)com.mitsheth.Fond`

4. **Add shared files to NSE target membership** (select each file → File Inspector → Target Membership):
   - `Shared/Constants/FondConstants.swift`
   - `Shared/Models/UserStatus.swift`
   - `Shared/Models/ConnectionState.swift`
   - `FondNotificationService/NotificationService.swift`

5. **Set deployment target:** NSE → General → Minimum Deployments → iOS 26.0

6. **Verify scheme:** Product → Scheme → Edit Scheme → Build tab → ensure FondNotificationService is listed

7. **Build and run on real device** (NSE does not work in Simulator)

---

## 1. Problem Diagnosis

### Current Architecture (what happens today)

When a partner sends a status update, two things fire simultaneously from `notifyPartner` Cloud Function:

**Path A — FCM push → main app background wakeup:**
1. FCM delivers push to device
2. iOS *may* wake main app in background
3. `AppDelegate.didReceiveRemoteNotification` fires
4. `PushManager.handlePushDataAsync()` runs:
   - Fetches OWN user doc from Firestore (network call #1)
   - Fetches PARTNER user doc from Firestore (network call #2)
   - Decrypts all fields using Keychain symmetric key
   - Writes plaintext to App Group UserDefaults
   - Calls `WidgetCenter.shared.reloadAllTimelines()`
5. WidgetKit calls `getTimeline()` → reads fresh App Group data → widget updates

**Path B — Direct APNs widget push:**
1. APNs delivers widget push to device
2. WidgetKit calls `getTimeline()` on `FondTimelineProvider`
3. `readEntry()` reads App Group UserDefaults
4. Returns whatever data is there (likely **stale** — Path A hasn't finished yet)

### Five Failure Points

| # | Failure | Impact | Severity |
|---|---------|--------|----------|
| 1 | **Silent push throttling** — iOS aggressively throttles `content-available` pushes. When app is force-quit, Low Power Mode is on, or device hasn't been used recently, iOS may not wake the app at all. | Widget never updates until user opens app | **Critical** |
| 2 | **Race condition** — Widget push (Path B) arrives before or simultaneously with FCM push (Path A). `getTimeline()` reads stale App Group data. | Widget shows old data, then *maybe* updates later if Path A succeeds and a second reload is triggered | **Critical** |
| 3 | **Double Firestore roundtrip** — `handlePushDataAsync()` makes two `getDocument()` calls (own doc + partner doc). Each is 200-800ms depending on network. | Adds 400-1600ms latency to the critical path | **High** |
| 4 | **Widget reload budget burn** — The stale widget push read burns a reload from the daily budget (40-70 reloads/day). The actual useful reload triggered by Path A is a second budget spend. | Could exhaust widget reload budget, causing updates to stop later in the day | **Medium** |
| 5 | **`content-available` on status pushes** — Status changes are sent as silent background pushes (no alert). These are the lowest priority for iOS and most likely to be dropped. | Status changes (the most common update type) are the least reliable | **High** |

---

## 2. Target Architecture

### Core Principle

> **By the time WidgetKit calls `getTimeline()`, fresh decrypted data MUST already be in App Group UserDefaults.**

### New Pipeline (after fix)

```
Partner sends update
    │
    ▼
Client writes to Firestore + calls notifyPartner Cloud Function
    │
    ▼
Cloud Function reads caller's encrypted fields from Firestore
    │
    ├── Sends FCM push WITH encrypted payload data (alert types)
    │       │
    │       ▼
    │   Notification Service Extension (NSE) intercepts
    │       │
    │       ├── Decrypts fields from push payload (no network needed)
    │       ├── Writes plaintext to App Group UserDefaults
    │       ├── Calls WidgetCenter.shared.reloadAllTimelines()
    │       ├── Modifies notification display text (optional)
    │       └── Calls contentHandler → notification shown
    │
    ├── Sends FCM push WITH encrypted payload data (silent types)
    │       │
    │       ▼
    │   Main app didReceiveRemoteNotification (if woken)
    │       │
    │       ├── Decrypts from push payload (no Firestore fetch needed)
    │       ├── Writes plaintext to App Group UserDefaults
    │       └── Calls WidgetCenter.shared.reloadAllTimelines()
    │
    └── Sends APNs widget push (delayed ~300ms, or removed)
            │
            ▼
        WidgetKit calls getTimeline() → reads FRESH App Group data
```

### Why This Works

1. **NSE is reliable** — Unlike `didReceiveRemoteNotification`, the Notification Service Extension runs for every alert-type push, even when the app is terminated or force-quit. It has its own process and ~30 seconds of execution time.

2. **No network needed** — Encrypted data arrives IN the push payload. Decryption is a local CryptoKit operation (~1ms). No Firestore roundtrip.

3. **No race condition** — The NSE writes to App Group BEFORE calling `reloadAllTimelines()`. The widget push (if sent at all) arrives after data is ready.

4. **Budget efficient** — One write + one reload, not two.

---

## 3. Implementation Plan — 5 Phases

### Phase 1: Cloud Function — Include Encrypted Payload

**File:** `functions/src/notifyPartner.ts`

**What changes:**
- After looking up `partnerUid`, read the **caller's** user document to get their encrypted fields
- Include encrypted fields in the FCM `data` payload: `encryptedStatus`, `encryptedMessage`, `encryptedName`, `encryptedHeartbeat`, `encryptedLocation`, `encryptedPromptAnswer`
- Add `"mutable-content": 1` to ALL push types (required for NSE interception)
- Convert silent pushes (status, promptAnswer) to low-priority alerts with `"mutable-content": 1` so the NSE can intercept them (NSE only runs for alert-type pushes)
- Remove or delay the direct APNs widget push — let the NSE or main app handle the `reloadAllTimelines()` call

**Payload size check:**
- APNs limit: 4KB (4096 bytes)
- Each encrypted field is ~50-200 bytes Base64 (AES-GCM: 12 byte nonce + ciphertext + 16 byte tag)
- `encryptedStatus`: ~60 bytes (status raw value is short, e.g. "available")
- `encryptedName`: ~80 bytes (display name up to ~30 chars)
- `encryptedMessage`: ~200 bytes (max 100 chars)
- `encryptedHeartbeat`: ~80 bytes (JSON like `{"bpm":72}`)
- `encryptedLocation`: ~120 bytes (JSON with lat/lon)
- `encryptedPromptAnswer`: ~200 bytes
- Total custom data: ~740 bytes worst case
- APS overhead + FCM headers: ~300 bytes
- **Total: ~1040 bytes — well within 4KB limit**

**Silent → low-priority alert conversion:**
- Status changes currently send `"content-available": 1` with no alert (silent push)
- Problem: NSE does NOT intercept silent pushes — only pushes with `"alert"` AND `"mutable-content": 1`
- Solution: Send ALL types as alerts with `"mutable-content": 1`. For status/promptAnswer types, use a minimal invisible-ish alert that the NSE can suppress or the user can configure via notification settings
- Alternative: Keep silent push as a fallback path, but the NSE alert path is the primary

**Key decision — what to do with widget push:**
- **Option A (recommended):** Keep widget push but delay it by 500ms using `setTimeout` after FCM send completes. This gives NSE time to write data before WidgetKit reads it.
- **Option B:** Remove widget push entirely, rely on NSE calling `reloadAllTimelines()`. Simpler, but loses the direct WidgetKit wakeup path.
- **Option C:** Keep parallel but accept occasional stale read. Least change but doesn't fix the core race condition.
- **Go with Option A** — belt and suspenders.

**Verification:** Deploy function, send test push, check Cloud Function logs for payload size and delivery confirmation.

---

### Phase 2: Notification Service Extension (NSE) — New Xcode Target

**New target:** `FondNotificationService` (Notification Service Extension)

**New files:**
- `FondNotificationService/NotificationService.swift` — Main NSE class
- `FondNotificationService/FondNotificationService.entitlements` — Entitlements file
- `FondNotificationService/Info.plist` — Extension Info.plist

**Entitlements (must match main app):**
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.mitsheth.Fond</string>
</array>
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.mitsheth.Fond</string>
</array>
```

**Shared code (add to NSE target membership in Xcode):**
- `Shared/Crypto/EncryptionManager.swift`
- `Shared/Crypto/KeychainManager.swift`
- `Shared/Constants/FondConstants.swift`
- `Shared/Models/UserStatus.swift` (for raw value parsing)
- `Shared/Models/ConnectionState.swift`

**NotificationService.swift logic:**

```
didReceive(_:withContentHandler:)
    │
    ├── Extract encrypted fields from userInfo["data"] dictionary
    │
    ├── Load symmetric key from shared Keychain (kSecAttrAccessGroup)
    │       └── If key missing → fall through, deliver original notification
    │
    ├── Decrypt each field using EncryptionManager
    │       ├── encryptedName → partnerName
    │       ├── encryptedStatus → partnerStatus
    │       ├── encryptedMessage → partnerMessage
    │       └── (heartbeat, location, promptAnswer as available)
    │
    ├── Write decrypted data to App Group UserDefaults
    │       └── Same keys as FirebaseManager.writePartnerDataToAppGroup()
    │
    ├── Call WidgetCenter.shared.reloadAllTimelines()
    │
    ├── (Optional) Modify notification content:
    │       ├── For "message" type: title = partnerName, body = decrypted message
    │       ├── For "nudge" type: title = "Fond", body = "{partnerName} is thinking of you 💛"
    │       └── For "status" type: suppress notification (or show subtle update)
    │
    └── Call contentHandler(bestAttemptContent)
```

**Critical implementation details:**

1. **Keychain access** — The NSE accesses the shared Keychain via `kSecAttrAccessGroup = "3P89U4WZAB.com.mitsheth.Fond"`. This is already set up in both main app and widget extension entitlements. The key is stored with `kSecAttrAccessibleAfterFirstUnlock` which means the NSE can read it as long as the device has been unlocked at least once since boot.

2. **App Group access** — The NSE writes to `UserDefaults(suiteName: "group.com.mitsheth.Fond")` using the same keys defined in `FondConstants`.

3. **`serviceExtensionTimeWillExpire()`** — If decryption takes too long (it won't — CryptoKit is <1ms), deliver the original unmodified notification as fallback. The main app background handler can still try Path A as a safety net.

4. **No Firebase SDK in NSE** — The NSE should NOT import Firebase. It doesn't need Firestore access (data comes from the push payload). Keep it lightweight for fast startup.

5. **Memory limit** — NSEs have a lower memory limit (~24MB). Since we're not doing any networking or image processing, just decryption, this is fine.

**Xcode setup steps (manual):**
1. File → New → Target → Notification Service Extension
2. Product Name: `FondNotificationService`
3. Bundle ID: `com.mitsheth.Fond.FondNotificationService`
4. Add App Groups capability → `group.com.mitsheth.Fond`
5. Add Keychain Sharing capability → `$(AppIdentifierPrefix)com.mitsheth.Fond`
6. Set shared source files to be members of both main app and NSE targets
7. Set deployment target to match main app (iOS 26)

---

### Phase 3: Update Main App Background Handler (Fallback Path)

**File:** `Fond/Shared/Services/PushManager.swift`

**What changes:**
- `handlePushDataAsync()` should FIRST try to decrypt data from the push payload (same as NSE)
- Only fall back to Firestore fetch if push payload doesn't contain encrypted fields (backward compatibility with old Cloud Function version, or for push types that don't include data)
- This makes the main app handler a fast local decryption (~1ms) instead of a slow network fetch (~1s)

**Updated flow:**
```
handlePushDataAsync(userInfo)
    │
    ├── Check: does userInfo contain "encryptedStatus" key?
    │
    ├── YES (new pipeline):
    │       ├── Decrypt from payload directly (no network)
    │       ├── Write to App Group
    │       ├── Reload widgets
    │       ├── Sync to Watch
    │       └── Return .newData
    │
    └── NO (legacy fallback):
            ├── Fetch from Firestore (existing code)
            ├── Decrypt, write App Group, reload widgets
            └── Return .newData
```

**Why keep both paths:**
- During rollout, some pushes may still use the old format
- If Cloud Function update hasn't deployed yet, the old Firestore-fetch path still works
- Edge case: if FCM truncates data fields for some reason, fallback to Firestore

**New helper method:**
```swift
/// Decrypts partner data directly from push payload (no network needed).
/// Returns true if payload contained encrypted data, false if fallback needed.
private func decryptFromPayload(_ userInfo: [AnyHashable: Any]) -> Bool
```

---

### Phase 4: Handle Silent Push Types (Status Changes)

**The NSE problem with silent pushes:**
- `UNNotificationServiceExtension` ONLY intercepts pushes that have BOTH:
  - An `alert` dictionary in the `aps` payload
  - `"mutable-content": 1`
- Silent pushes (`"content-available": 1` with no alert) bypass the NSE entirely
- Status changes and prompt answers are currently sent as silent pushes

**Solution options:**

**Option A — Convert all pushes to alert-type (recommended):**
- Send ALL notification types as alerts with `"mutable-content": 1`
- For types that shouldn't show a visible notification (status, promptAnswer):
  - NSE sets `bestAttemptContent.title = ""` and `bestAttemptContent.body = ""` → iOS won't display it, but NSE still runs and writes to App Group
  - OR: Use a notification category with custom dismiss action
  - OR: Set `bestAttemptContent.sound = nil` and use InterruptionLevel.passive
- ALSO include `"content-available": 1` so the main app ALSO gets woken (belt + suspenders)

**Option B — Two parallel pushes per update:**
- One alert push (with mutable-content) targeted at NSE → writes App Group
- One silent push (content-available) targeted at main app → backup path
- Downside: doubles FCM cost and push volume

**Option C — Accept silent push unreliability for status changes:**
- Only use NSE path for message/nudge/heartbeat (already alert-type)
- Status changes remain on the unreliable silent push path
- Downside: the most common update type is the least reliable

**Go with Option A.** The NSE can suppress the notification display while still doing the critical App Group write.

**Implementation in notifyPartner.ts:**
```typescript
// ALL types now get an alert with mutable-content for NSE interception
const apsPayload = {
    "alert": {
        "title": "Fond",
        "body": ALERT_BODY[data.type] || "Update from your person",
    },
    "mutable-content": 1,
    "content-available": 1,
    "sound": isAlert ? "default" : undefined,
    // Category lets the NSE and user control notification behavior
    "category": `fond.${data.type}`,
};
```

**Implementation in NSE:**
```swift
// For silent-equivalent types, suppress the visible notification
switch type {
case "status", "promptAnswer":
    // Write data to App Group (critical), but suppress display
    bestAttemptContent.title = ""
    bestAttemptContent.body = ""
    bestAttemptContent.sound = nil
case "message", "nudge", "heartbeat":
    // Show the notification with decrypted content
    bestAttemptContent.title = partnerName
    bestAttemptContent.body = decryptedMessage ?? alertBody
}
```

**Testing note:** Empty title + body may still show a minimal notification on some iOS versions. If so, use `UNNotificationContent.filterCriteria` or notification categories with hidden preview to fully suppress. Test on device.

---

### Phase 5: Verification & Cleanup

**Testing checklist:**

| Test Case | Expected Result | How to Verify |
|-----------|----------------|---------------|
| Partner sends status, my app is in foreground | Widget updates within ~1s, Firestore listener also updates ConnectedView | Visual check + console logs |
| Partner sends status, my app is backgrounded | Widget updates within ~2s via NSE | Lock screen → check widget. Console: `[NSE] Decrypted and wrote to App Group` |
| Partner sends status, my app is force-quit | Widget updates within ~2s via NSE | Force quit app → partner sends → check widget |
| Partner sends message, my app is backgrounded | Notification shows decrypted message text, widget updates | Check notification banner text matches actual message |
| Partner sends nudge, my app is terminated | Notification shows "thinking of you", widget updates | Force quit → send nudge → check |
| Low Power Mode on, app backgrounded | Widget still updates (NSE runs regardless of LPM) | Enable LPM → test |
| Device just rebooted (before first unlock) | Keychain inaccessible → notification shows generic text, widget stale | Reboot → send push before unlocking. After unlock, next push should work |
| Widget push token registered | Firestore device doc has `widgetPushToken` field | Check Firestore via Firebase console or MCP |
| Rapid consecutive updates (3 in 10 seconds) | All three update App Group, last state wins on widget | Send 3 status changes rapidly |
| Unlink while app is backgrounded | Widget shows "Not Connected" | Unlink from partner device → check widget |

**Cleanup tasks:**
- Remove the Firestore-fetch-first logic from `handlePushDataAsync()` (keep as fallback only)
- Update `docs/01-next-steps-open-questions.md` with the fix details
- Update `docs/03-current-status.md` with new file list
- Consider removing the direct APNs widget push entirely once NSE is proven reliable (simplifies Cloud Function, removes the `apnsHelper.ts` dependency for update pushes — keep it only for `unlinkConnection`)

---

## 4. File Change Summary

### New Files

| File | Target | Purpose |
|------|--------|---------|
| `FondNotificationService/NotificationService.swift` | NSE | Intercepts pushes, decrypts payload, writes App Group, reloads widgets |
| `FondNotificationService/FondNotificationService.entitlements` | NSE | App Group + Keychain access |
| `FondNotificationService/Info.plist` | NSE | Extension point identifier |

### Modified Files

| File | Target | Changes |
|------|--------|---------|
| `functions/src/notifyPartner.ts` | Cloud Functions | Read caller's encrypted fields, include in FCM payload, add mutable-content to all types, delay widget push |
| `Fond/Shared/Services/PushManager.swift` | Main app | Try payload-first decryption before Firestore fallback |
| `Fond/Shared/Crypto/EncryptionManager.swift` | Main app + NSE | Add to NSE target membership (no code changes) |
| `Fond/Shared/Crypto/KeychainManager.swift` | Main app + NSE | Add to NSE target membership (no code changes) |
| `Fond/Shared/Constants/FondConstants.swift` | Main app + NSE + Widget | Add to NSE target membership (no code changes) |
| `Fond/Shared/Models/UserStatus.swift` | Main app + NSE | Add to NSE target membership (no code changes) |
| `Fond/Shared/Models/ConnectionState.swift` | Main app + NSE | Add to NSE target membership (no code changes) |

### Xcode Manual Steps

1. **Add NSE target:** File → New → Target → Notification Service Extension → "FondNotificationService"
2. **Bundle ID:** `com.mitsheth.Fond.FondNotificationService`
3. **Capabilities:** Add App Groups (`group.com.mitsheth.Fond`) + Keychain Sharing (`$(AppIdentifierPrefix)com.mitsheth.Fond`)
4. **Target membership:** Add shared Swift files to NSE target (see table above)
5. **Deployment target:** Set NSE to iOS 26 (match main app)
6. **Scheme:** Ensure NSE builds with main app scheme

### Deploy Steps

1. `cd functions && npm run build && firebase deploy --only functions` (Phase 1)
2. Build and run from Xcode (Phases 2-4)
3. Test on real device (Phase 5) — NSE does not work in Simulator

---

## 5. Architecture Decisions

### Why NSE over just improving the background handler?

| Factor | Background Handler (`didReceiveRemoteNotification`) | Notification Service Extension |
|--------|-----------------------------------------------------|-------------------------------|
| Runs when app is force-quit | **No** — iOS won't wake a force-quit app for silent pushes | **Yes** — NSE is a separate process |
| Runs in Low Power Mode | **Unreliable** — iOS aggressively throttles | **Yes** — runs for all alert pushes |
| Runs for silent pushes | Yes (when not throttled) | **No** — only for alert + mutable-content |
| Has Keychain access | Yes | **Yes** — with shared access group |
| Has App Group access | Yes | **Yes** — with shared app group |
| Can call `reloadAllTimelines()` | Yes | **Yes** |
| Execution time | ~30 seconds | ~30 seconds |
| Reliability for our use case | ~60-70% | ~95%+ |

### Why include encrypted data in push vs. fetch from Firestore?

- **Latency:** Push payload decryption is <1ms. Firestore fetch is 200-1500ms.
- **Reliability:** No network dependency in the critical path. Works on airplane mode (if push was already delivered).
- **Privacy preserved:** The push payload still contains only ciphertext. Apple and Google see Base64 blobs, not plaintext. Only the device with the symmetric key in Keychain can decrypt.
- **Size:** Our encrypted fields total ~1KB worst case. APNs limit is 4KB. Plenty of headroom.

### Why convert silent pushes to alert+mutable-content?

The NSE is our most reliable path, but it only intercepts alert-type pushes with `mutable-content: 1`. Silent pushes bypass it entirely. By converting all push types to alerts, we route everything through the reliable NSE path. The NSE can then suppress the visible notification for types that shouldn't show one (status changes, prompt answers).

### Why keep the main app background handler?

Belt and suspenders. The NSE handles ~95% of cases. The remaining ~5% (device just booted, key not synced yet, edge cases) may need the main app handler as fallback. It also handles the foreground case where `ConnectedView`'s Firestore listener is already doing real-time updates.

---

## 6. Build Order

Execute phases in this order. Each phase is independently deployable and backward-compatible.

1. **Phase 1** — Cloud Function changes (can deploy independently, existing app still works)
2. **Phase 2** — NSE target creation + implementation
3. **Phase 3** — Main app PushManager update (payload-first decryption)
4. **Phase 4** — Silent push → alert conversion (requires Phase 1 + 2 to be ready)
5. **Phase 5** — Testing on real devices + cleanup

**Estimated implementation time:** 2-3 sessions

---

## 7. References

- [Apple: Keeping a Widget Up to Date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [WWDC25 Session 278: What's New in Widgets](https://developer.apple.com/videos/play/wwdc2025/278/) — Widget push updates section
- [Apple: UNNotificationServiceExtension](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension)
- [Apple: Creating the Remote Notification Payload](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CreatingtheNotificationPayload.html)
- [Apple: Updating Widgets with WidgetKit Push Notifications](https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications)
- [Firebase: Customize Messages Across Platforms](https://firebase.google.com/docs/cloud-messaging/customize-messages/cross-platform)
