# Fond — Feature Expansion Implementation Plan

> Author: Senior iOS Architect Review
> Created: February 24, 2026
> Status: Pre-implementation — all decisions subject to review before first commit
>
> **Scope:** 7 new features, zero new backend services, zero new Firebase products.
> Every feature reuses the existing encrypted Firestore write → push → App Group → widget pipeline.

---

## Guiding Principles

1. **No new infrastructure.** Every feature routes through the existing `users/{uid}` document, `notifyPartner` Cloud Function, App Group bridge, and WidgetKit timeline. If a feature requires a new Cloud Function or Firebase product, it must justify itself.
2. **Encrypt everything personal.** Location coordinates, heartbeat data, daily prompt answers — all encrypted client-side with the existing AES-256-GCM pipeline before touching Firestore.
3. **Widget is the product.** Every feature must express itself in at least one widget family. If it can't appear on a widget, it doesn't belong in v1.
4. **Degrade gracefully.** If location permission is denied, if HealthKit isn't available, if the watch isn't paired — the app must never crash, never show broken UI, and never lose existing functionality.
5. **One model change, one migration.** All Firestore schema additions go into a single coordinated update so we don't ship multiple client versions with incompatible expectations.

---

## Table of Contents

1. [Unified Data Model Changes](#1-unified-data-model-changes)
2. [Feature 1: Days-Together Counter + Countdown Widget](#2-feature-1-days-together-counter--countdown-widget)
3. [Feature 2: Expanded Status Vocabulary](#3-feature-2-expanded-status-vocabulary)
4. [Feature 3: One-Tap "Thinking of You" from watchOS](#4-feature-3-one-tap-thinking-of-you-from-watchos)
5. [Feature 4: Daily Prompt](#5-feature-4-daily-prompt)
6. [Feature 5: Distance Widget](#6-feature-5-distance-widget)
7. [Feature 6: StandBy Mode Optimization](#7-feature-6-standby-mode-optimization)
8. [Feature 7: Heartbeat Snapshot Sharing](#8-feature-7-heartbeat-snapshot-sharing)
9. [Build Order & Dependencies](#9-build-order--dependencies)
10. [File Inventory (New + Modified)](#10-file-inventory-new--modified)
11. [Cloud Function Changes](#11-cloud-function-changes)
12. [Firestore Rules Changes](#12-firestore-rules-changes)
13. [Risk Register](#13-risk-register)

---

## 1. Unified Data Model Changes

All 7 features share a single coordinated schema expansion. This section defines every change to Firestore, App Group, WatchConnectivity, and Swift models — so individual feature sections can reference them without repetition.

### 1.1 Firestore `users/{uid}` Document — New Fields

```
users/{uid}
├── (existing) publicKey, encryptedName, encryptedStatus, encryptedMessage,
│              lastUpdatedAt, connectionId, partnerUid, createdAt
│
├── encryptedLocation: String?        // AES-256-GCM(JSON: {lat, lon, updatedAt})
├── encryptedHeartbeat: String?       // AES-256-GCM(JSON: {bpm, updatedAt})
├── encryptedPromptAnswer: String?    // AES-256-GCM(JSON: {promptId, answer, updatedAt})
├── anniversaryDate: Timestamp?       // PLAINTEXT — not sensitive, needed for widget math
├── countdownDate: Timestamp?         // PLAINTEXT — same rationale
├── countdownLabel: String?           // AES-256-GCM("Spring break trip!")
```

**Why `anniversaryDate` and `countdownDate` are plaintext:**
These are the only two fields that the widget needs for client-side date arithmetic. They contain calendar dates with no location, content, or behavioral data. Encrypting them would mean the widget (which has no Firebase SDK) could never compute "Day 347" independently — it would be stale until the main app decrypts and writes to App Group. The privacy risk of a calendar date is negligible compared to the UX cost. Both partners set their own copy (not a shared field) so they can customize independently.

**Why location/heartbeat/prompt are encrypted:**
GPS coordinates, biometric data, and personal answers are deeply sensitive. They follow the same `EncryptionManager.encrypt()` → Base64 → Firestore path as everything else. Firebase never sees plaintext.

### 1.2 Firestore `connections/{id}` Document — New Fields

```
connections/{id}
├── (existing) user1, user2, isActive, createdAt
│
├── anniversaryDate: Timestamp?       // Shared — set once during pairing or in settings
```

**Why on the connection doc:** The anniversary date is a property of the relationship, not an individual user. Having it on the connection doc means both users see the same "Day X" count. It's set once (during pairing or first setup) and rarely changes. It's plaintext for the same widget-math reason above.

### 1.3 `FondUser.swift` Model Update

```swift
struct FondUser: Codable, Identifiable, Sendable {
    // ... existing fields ...
    
    /// AES-256-GCM ciphertext of location JSON: {"lat": Double, "lon": Double}
    var encryptedLocation: String?
    
    /// AES-256-GCM ciphertext of heartbeat JSON: {"bpm": Int}
    var encryptedHeartbeat: String?
    
    /// AES-256-GCM ciphertext of prompt answer JSON: {"promptId": String, "answer": String}
    var encryptedPromptAnswer: String?
    
    /// Plaintext anniversary date (not sensitive, needed for widget date math).
    var anniversaryDate: Date?
    
    /// Plaintext countdown target date.
    var countdownDate: Date?
    
    /// AES-256-GCM ciphertext of the countdown label.
    var countdownLabel: String?
}
```

### 1.4 `FondConstants.swift` — New App Group Keys

```swift
// MARK: - New App Group Keys (Feature Expansion)

// Days Together / Countdown
static let anniversaryDateKey = "anniversaryDate"
static let countdownDateKey = "countdownDate"
static let countdownLabelKey = "countdownLabel"

// Distance
static let distanceMilesKey = "distanceMiles"
static let partnerCityKey = "partnerCity"    // Reverse-geocoded display name

// Heartbeat
static let partnerHeartbeatKey = "partnerHeartbeat"
static let partnerHeartbeatTimeKey = "partnerHeartbeatTime"

// Daily Prompt
static let dailyPromptIdKey = "dailyPromptId"
static let dailyPromptTextKey = "dailyPromptText"
static let myPromptAnswerKey = "myPromptAnswer"
static let partnerPromptAnswerKey = "partnerPromptAnswer"

// Thinking of You (nudge)
static let lastNudgeTimeKey = "lastNudgeTime"
```

### 1.5 `UserStatus.swift` — Expanded Enum

See Feature 2 for the full expansion. The enum grows from 4 cases to ~16, grouped by category.

### 1.6 WatchConnectivity Context — New Keys

The `WatchSyncManager.syncPartnerData()` dictionary expands:

```swift
context["partnerHeartbeat"] = bpm          // Int
context["partnerHeartbeatTime"] = timestamp // TimeInterval
context["distanceMiles"] = miles           // Double
context["anniversaryDays"] = days          // Int
context["countdownDays"] = days            // Int?
context["dailyPromptText"] = text          // String
context["partnerPromptAnswer"] = answer    // String?
```

### 1.7 `FondMessage.EntryType` — New Cases

```swift
enum EntryType: String, Codable, Sendable {
    case status
    case message
    case nudge           // "thinking of you" tap
    case heartbeat       // heartbeat snapshot
    case promptAnswer    // daily prompt response
}
```

This extends the history subcollection to log all new interaction types. The `notifyPartner` Cloud Function already accepts a `type` string — we just pass new values. The Cloud Function doesn't need to understand these types; it just fans out the push.

### 1.8 notifyPartner Cloud Function — Minimal Change

The existing function accepts `type: string` and passes it through to FCM data payload. Current validation restricts to `"status" | "message"`. We relax this:

```typescript
// BEFORE
if (!data.type || !["status", "message"].includes(data.type)) {

// AFTER  
const validTypes = ["status", "message", "nudge", "heartbeat", "promptAnswer"];
if (!data.type || !validTypes.includes(data.type)) {
```

The Cloud Function remains content-blind. It doesn't read, decrypt, or interpret any payload. It only knows "user X sent something of type Y" and fans out pushes. Privacy preserved.

---

## 2. Feature 1: Days-Together Counter + Countdown Widget

### Emotional Value
A days-together counter creates compounding emotional attachment. At day 100, users smile. At day 500, they screenshot. At day 1,000, they'll never delete the app. Countdown widgets reduce LDR anxiety — "14 days until I see you" reframes distance as temporary.

### Architecture

**Pure client-side date math.** The widget reads `anniversaryDate` and/or `countdownDate` from App Group UserDefaults, computes the day count, and renders. No Firestore reads, no Cloud Functions, no encryption needed for the computation itself.

**Data flow:**
1. User sets anniversary date in Settings (date picker)
2. App writes `anniversaryDate` to Firestore `connections/{id}` document (plaintext Timestamp) + to App Group
3. Firestore listener on partner's device picks up the connection doc change → writes to their App Group
4. Widget reads from App Group, computes `Calendar.current.dateComponents([.day], from: anniversary, to: .now).day`
5. Countdown works identically but user sets `countdownDate` + `countdownLabel` on their own user doc

**Why anniversary on connection doc, countdown on user doc:**
Anniversary is shared — both partners see the same "Day 347." Countdown is personal — one partner might set "Spring break trip" while the other hasn't set anything. Countdown label is encrypted (could reveal travel plans); countdown date is plaintext (needed for widget math).

### Widget Families

| Family | Layout | Example |
|--------|--------|---------|
| `accessoryInline` | `"Day 347 with Alex 💛"` or `"14 days until NYC ✈️"` |
| `accessoryCircular` | Large number centered, "days" label below, heart icon | `347` / `days` |
| `systemSmall` | Number hero (72pt), "days together" label, partner name | Beautiful ambient counter |
| `systemMedium` | Split: days-together left, countdown right (if set) | Dual purpose |

### Implementation Plan

**New file:** `Shared/Models/DateWidgetData.swift` — Struct holding computed widget data.

**Modified files:**
- `SettingsView.swift` — Add date pickers for anniversary + countdown. Countdown has an optional text label field.
- `FirebaseManager.swift` — New methods: `setAnniversaryDate()`, `setCountdownDate()`. Anniversary writes to connection doc, countdown writes to user doc.
- `ConnectedView.swift` — Display days-together count somewhere subtle (maybe in the toolbar or below partner card).
- `FondConstants.swift` — New App Group keys (already defined above).
- `widgets.swift` — New widget views for date content. New `Intent`-based configuration so users choose between "status widget" and "days widget" at add time.

**New widget:** `FondDateWidget` — A second Widget in the `FondWidgetBundle`, specifically for date-based display. This is better than overloading the existing status widget because users should be able to have both on their home screen simultaneously.

**Edge cases:**
- Anniversary date not set → widget shows "Set anniversary in Fond" placeholder
- Countdown date in the past → show "🎉 It's here!" for 24 hours, then hide
- Both dates set → systemMedium shows both side-by-side; smaller families let user choose via widget configuration (AppIntentConfiguration)
- Date set by partner before user opens app → Firestore listener picks it up on next app open

### Firestore Rules Impact
The connection doc already allows read/update by connection members. Anniversary date write just needs:
```
allow update: if isSignedIn() && isConnectionMember(resource.data)
  && request.resource.data.diff(resource.data).affectedKeys()
     .hasOnly(['anniversaryDate']);
```
Consider adding this as an additional rule clause, or just rely on the existing broad update permission for connection members.

---

## 3. Feature 2: Expanded Status Vocabulary

### Emotional Value
Four statuses (available/busy/away/sleeping) is functional but emotionally flat. Couples want to express "I'm thinking about you", "I'm stressed", "I miss you", "I'm excited." The status is the primary signal on the widget — enriching it enriches every glance.

### Architecture

**Backward-compatible enum expansion.** The `UserStatus` enum grows from 4 to ~16 cases. Since statuses are stored as encrypted strings of the raw value (e.g., `"available"`), old clients that don't recognize a new status gracefully fall back to displaying the raw emoji. No migration needed.

**Grouped picker UI.** The flat 4-pill row becomes a scrollable grid or section-based picker, possibly a half-sheet. Categories: Availability, Mood, Activity, Love.

### Proposed Status Set

```swift
enum UserStatus: String, Codable, CaseIterable, Sendable {
    // Availability (existing — keep backward compat)
    case available
    case busy
    case away
    case sleeping
    
    // Mood
    case happy
    case stressed
    case sad
    case excited
    case calm
    
    // Activity
    case working
    case driving
    case eating
    case exercising
    
    // Love (the differentiator — no other app has status-as-affection)
    case thinkingOfYou
    case missYou
    case lovingYou
}
```

Each case gets: `emoji`, `displayName`, `category` (for picker grouping), `accentColor`.

### Custom Meanings — Future Consideration

The competitive research surfaced demand for "secret language" status meanings. Couples want to assign private meaning to specific emoji (e.g., 🦊 means "I'm thinking about our trip"). This is a v2 feature — it requires a custom emoji picker, meaning storage, and sync. For now, the expanded vocabulary covers the emotional range without custom meanings. Note it in the design doc as a future direction.

### Implementation Plan

**Modified files:**
- `UserStatus.swift` — Expand enum, add `category` property, update `emoji`/`displayName`/`accentColor` computed properties.
- `ConnectedView.swift` — Replace flat 4-pill row with a category-based picker. Options: (a) horizontal scrolling with section headers, (b) sheet picker with a grid, (c) contextual menu. Recommend (b) — a half-sheet with a 4×4 grid feels natural and doesn't clutter the hub.
- `WatchConnectedView.swift` — Status display adapts automatically (reads raw string + emoji).
- `widgets.swift` — Status display adapts automatically (same mechanism).

**No Firestore changes.** The encrypted status field already stores the raw value string. New raw values just flow through.

**No Cloud Function changes.** `notifyPartner` is content-blind.

**Backward compatibility:** If user A on the new version sets status to `thinkingOfYou` and user B is on an older version, user B's `UserStatus(rawValue:)` returns nil. The listener in `ConnectedView` falls back: `let status = UserStatus(rawValue: statusRaw)` — if nil, show the raw string with a default emoji. Add a `static func fromRaw(_ raw: String) -> (emoji: String, displayName: String)` fallback that handles unknown values gracefully.

**Design consideration:** The status picker is one of the most-used UI elements. The redesign must not add friction. One tap should still set a status. The sheet should open fast, dismiss fast, and the grid items should be large enough for confident tapping. Haptic on selection, immediate dismiss.

---

## 4. Feature 3: One-Tap "Thinking of You" from watchOS

### Emotional Value
This is the single feature most aligned with the research finding that couples want "lightweight thinking-of-you signals." A tap on the wrist → partner's phone buzzes with a warm notification + their widget updates. Competes with $100 Bond Touch bracelets at zero hardware cost.

### Architecture

**Bidirectional WatchConnectivity + existing push pipeline.**

Currently the watch is read-only: iPhone → Watch via `updateApplicationContext`. We add the reverse: Watch → iPhone via `sendMessage()` (if reachable) or `transferUserInfo()` (if not).

**Full data flow:**
1. User taps complication or button on watch
2. `WatchDataStore` calls `WCSession.default.sendMessage(["action": "nudge"])` (real-time if iPhone reachable) or `transferUserInfo(["action": "nudge"])` (queued if not)
3. `WatchSyncManager` on iPhone receives the message in `session(_:didReceiveMessage:)` or `session(_:didReceiveUserInfo:)`
4. WatchSyncManager calls `FirebaseManager.sendNudge(uid:connectionId:)`
5. `sendNudge` writes a minimal update to user doc (`lastUpdatedAt` + type field) + appends to history + calls `notifyPartner(type: "nudge")`
6. Partner receives FCM push → notification banner "💛 [Name] is thinking of you" → widget reloads → watch buzzes

**Why `sendMessage` + `transferUserInfo` fallback:**
`sendMessage` is real-time but requires the iPhone to be reachable (nearby, app in memory). `transferUserInfo` is queued — guaranteed delivery but may be delayed. For a "thinking of you" nudge, immediacy matters, so we try `sendMessage` first and fall back to `transferUserInfo`. We never use `updateApplicationContext` for watch→phone because it's designed for state sync, not events (each new context overwrites the previous).

### Watch UI

**Complication:** A small heart icon. Tapping it opens a confirmation view with a single "Send 💛" button. We don't send on complication tap alone — accidental wrist bumps would spam the partner. The one extra tap is intentional friction.

**In-app button:** On `WatchConnectedView`, below the partner card, add a glass-styled "Thinking of You 💛" button. Same rate limiting as the phone app (5s cooldown with visual ring).

**After sending:** Brief haptic + checkmark animation on watch. No need to wait for server confirmation — fire-and-forget, same as phone sends.

### iPhone Notification

```
Title: "Fond"
Body: "💛 [Partner Name] is thinking of you"
Sound: default
```

This is a visible alert notification (not silent) because the whole point is to interrupt the partner's day with warmth. The `notifyPartner` function already handles alert vs. silent based on type — we add `"nudge"` to the alert category alongside `"message"`.

### Implementation Plan

**New files:**
- `WatchNudgeSender.swift` (watchOS target) — Handles the send logic, rate limiting, haptic feedback on the watch side.

**Modified files:**
- `WatchDataStore.swift` — Add `sendNudge()` method that uses `WCSession.sendMessage`/`transferUserInfo`.
- `WatchConnectedView.swift` — Add "Thinking of You" button with cooldown ring.
- `WatchSyncManager.swift` — Add `session(_:didReceiveMessage:)` and `session(_:didReceiveUserInfo:)` delegates. On receiving `["action": "nudge"]`, trigger the Firestore write + push.
- `FirebaseManager.swift` — New method `sendNudge(uid:connectionId:)` — writes to history, calls notifyPartner.
- `FondMessage.EntryType` — Add `.nudge` case.
- `notifyPartner.ts` — Add `"nudge"` to valid types + set it as alert (not silent).
- `HistoryView.swift` — Render nudge entries as a compact "💛 Thinking of you" pill (like status change pills, not full chat bubbles).

**Edge cases:**
- iPhone not reachable → `transferUserInfo` queues it. When iPhone becomes reachable, it processes the queue. Nudge is still sent but delayed. Acceptable — the partner sees it when they next use their phone.
- Watch not paired → Feature simply doesn't appear on iPhone. No degradation.
- Rate limiting → 5s cooldown on watch side (client-enforced). Server-side rate limiting in Cloud Function is still a future TODO — acceptable for now since the rate limit on send effectively prevents abuse.
- Both partners send nudge simultaneously → Both receive each other's. No conflict.

---

## 5. Feature 4: Daily Prompt

### Emotional Value
Creates a daily shared ritual — the #2 most valued feature pattern in the research. "My girlfriend and I start our mornings by answering the question." Prompts create conversation starters without the pressure of "what should we talk about?"

### Architecture

**Bundled JSON file + existing pipeline.** No server-side content delivery. No new Cloud Function. No new Firestore collection.

**Prompt rotation:** Deterministic by date. `let index = Calendar.current.ordinality(of: .day, in: .era, for: Date())! % prompts.count`. Both partners always see the same prompt on the same day without any sync. The index is purely date-derived — no server coordination needed.

**Answer flow:**
1. App displays today's prompt (from bundled JSON)
2. User types answer → `EncryptionManager.encrypt(answer)` → writes to `users/{uid}/encryptedPromptAnswer`
3. `notifyPartner(type: "promptAnswer")` pushes to partner
4. Partner's Firestore listener picks up encrypted answer → decrypts → shows in UI + writes to App Group
5. Widget can show: "Today's Q: [prompt text]" + partner's answer (if submitted)

**Both-answer reveal mechanic (optional — recommend for v1):**
Paired's most-loved UX is "answer independently, then reveal each other." Implementation: the app shows the prompt + your text field. Once you submit, you see "Waiting for [partner]..." until their `encryptedPromptAnswer` field updates. Then both answers appear side-by-side. This requires no server logic — the client simply checks: (a) did I answer? (b) did partner answer? If both, show both. If only me, show "waiting." If only partner, show prompt + input.

### Prompt Content

Ship with 365 prompts in `DailyPrompts.json`. Categories:

- **Light/Fun:** "If we could swap lives for a day, what would you do first?" / "What's a song that reminds you of us?"
- **Reflective:** "What's something I did recently that made you feel loved?" / "What's one thing you want us to do more of?"
- **Playful:** "Quick — pizza or tacos for the rest of your life?" / "What would our couple reality show be called?"
- **Future:** "Where do you see us in 5 years?" / "What's a trip you want to take together?"
- **Appreciation:** "What's your favorite memory of us?" / "What's something about me that surprised you?"

Each prompt: `{ "id": "p001", "text": "...", "category": "light" }`

### Widget Expression

| Family | Layout |
|--------|--------|
| `accessoryRectangular` | "Q: [prompt text truncated]" + partner answer preview |
| `systemSmall` | Prompt text centered, "Tap to answer" CTA |
| `systemMedium` | Full prompt + both answers side-by-side (if answered) |

### Implementation Plan

**New files:**
- `Resources/DailyPrompts.json` — 365 prompts (can ship with 30-50 initially and expand)
- `Shared/Models/DailyPrompt.swift` — `struct DailyPrompt: Codable { let id: String; let text: String; let category: String }`
- `Shared/Services/DailyPromptManager.swift` — Loads JSON, computes today's prompt by date, manages local answer state
- `Views/DailyPromptCard.swift` — The prompt display + answer input UI, embeddable in ConnectedView

**Modified files:**
- `ConnectedView.swift` — Add daily prompt card below partner card (or as a collapsible section). This is the main decision point — does it live on the hub or as a sheet? Recommend: on the hub, below the status picker, as a compact card that expands on tap. Keeps the daily ritual visible without requiring navigation.
- `FirebaseManager.swift` — New method `submitPromptAnswer(uid:connectionId:answer:promptId:)`. Writes encrypted answer to user doc + history.
- `FondConstants.swift` — New App Group keys for prompt data.
- `widgets.swift` — New views for prompt display in relevant families.
- `FondMessage.EntryType` — Add `.promptAnswer` case.

**Edge cases:**
- User opens app at 11:59 PM, types answer, submits at 12:01 AM → The prompt ID is captured at display time, not submit time. Answer is associated with the prompt they saw.
- Both users on different timezones → Both see the same prompt because rotation is by UTC day, not local day. This is intentional — they should discuss the same question.
- Content exhaustion at day 366 → Prompts loop. By then, answers from a year ago are forgotten. If users complain, this is a great signal to invest in more content.
- Prompt not answered by either partner → Widget shows "Today: [prompt]" with no answers. No nag notifications — this should feel optional and fun, not obligatory.

---

## 6. Feature 5: Distance Widget

### Emotional Value
"347 miles apart" on the lock screen acknowledges the distance while making it concrete and manageable. When the number drops to "0.3 miles" during a visit, that moment of delight is powerful. Research showed LDR couples cite distance widgets as anxiety-reducing.

### Architecture

**Lazy location capture → encrypt → Firestore → client-side haversine.**

No continuous background location. No geofencing. No new Cloud Function. Location is captured opportunistically and the distance calculation happens entirely on the receiving device.

**Data flow:**
1. App foregrounds → `CLLocationManager.requestLocation()` (one-shot)
2. Receive `CLLocation` → round to 2 decimal places (~1.1km precision) → create JSON `{"lat": 37.78, "lon": -122.41}`
3. `EncryptionManager.encrypt(json)` → write to `users/{uid}/encryptedLocation`
4. Existing Firestore listener on partner's device picks up the change
5. Partner's app decrypts both own + partner location → `haversineDistance(loc1, loc2)` → writes distance (miles/km) to App Group
6. Widget reads from App Group and displays

**Why 2 decimal places:** 37.78 resolves to ~1.1km. This is city-level precision — enough for meaningful distance display, imprecise enough that it doesn't reveal exact address. We could go to 1 decimal (~11km) for even more privacy, but that makes "0.3 miles apart" impossible. 2 decimals is the right balance.

**Reverse geocoding for display:** After getting coordinates, call `CLGeocoder().reverseGeocodeLocation()` to get a city name. Store the city name in App Group as `partnerCity` for display: "347 mi — San Francisco ↔ New York". The city name is derived locally on the partner's device from the decrypted coordinates — it never touches Firestore.

**Update triggers:**
- App foreground (every time)
- Background app refresh (iOS decides frequency — typically every few hours)
- Manual pull-to-refresh in app
- NOT on a timer, NOT continuous, NOT geofenced

### Privacy Design

This is the most privacy-sensitive feature. Architecture choices:

1. **Coordinates encrypted before Firestore.** Firebase never sees location data.
2. **Precision limited to ~1km.** Not enough to identify a specific building.
3. **Location permission is optional.** If denied, the distance feature simply doesn't appear. All other features work normally. No nag screens.
4. **No location history.** We don't append location to the history subcollection. The `encryptedLocation` field on the user doc is overwritten each time — only the latest location exists.
5. **City name derived locally.** Reverse geocoding happens on-device, never server-side.
6. **Clear permission rationale.** The location permission prompt explains: "Fond uses your location to show your partner how far apart you are. Your exact location is encrypted and only visible to your partner."

### Widget Families

| Family | Layout | Example |
|--------|--------|---------|
| `accessoryInline` | `"347 mi apart 📍"` | Lock screen inline |
| `accessoryCircular` | Distance number centered, "mi" label below | `347` / `mi` |
| `systemSmall` | Large distance number, city names, contextual unit | "347 mi" / "SF ↔ NYC" / "~5hr drive" |

### Contextual Display

Beyond raw miles, offer contextual framing that makes distance feel smaller:

```swift
func contextualDistance(_ miles: Double) -> String {
    if miles < 1 { return "Right here 💛" }
    if miles < 30 { return "\(Int(miles)) mi — a quick drive" }
    if miles < 300 { return "\(Int(miles)) mi — \(Int(miles / 60))hr drive" }
    return "\(Int(miles)) mi — \(String(format: "%.1f", miles / 500))hr flight"
}
```

### Implementation Plan

**New files:**
- `Shared/Services/LocationManager.swift` — Wraps CLLocationManager. One-shot location request. Handles permission flow. Rounds coordinates. Encrypts and writes to Firestore. Reverse geocodes for city name. `#if canImport(CoreLocation)` guarded (not available on widget target).

**Modified files:**
- `ConnectedView.swift` — Display distance somewhere subtle (below partner card timestamp, or in the toolbar). Trigger location update on appear.
- `FondApp.swift` — Request location on app foreground (via `scenePhase` observer or AppDelegate).
- `FirebaseManager.swift` — New method `updateLocation(uid:lat:lon:)`. Encrypts and writes to user doc. New listener logic: when partner's `encryptedLocation` changes, decrypt, compute distance, write to App Group.
- `FondConstants.swift` — New App Group keys (defined above).
- `widgets.swift` — New distance views for applicable families.
- `Info.plist` — Add `NSLocationWhenInUseUsageDescription` with privacy-focused copy.

**New widget:** Consider whether distance is a separate widget (`FondDistanceWidget`) or a configuration option on the existing date/status widgets. Recommend: separate widget. Users should be able to place a small distance widget on their lock screen independently.

**Edge cases:**
- Location permission denied → Distance feature hidden everywhere. No broken UI. Settings shows "Enable location to see distance" with a link to System Settings.
- Partner hasn't shared location yet → Widget shows "Waiting for [name]'s location" or simply omits distance.
- Both partners in same city → Show exact distance: "0.8 mi apart." If < 0.1 mi: "Right here 💛"
- One partner on airplane (no location update) → Stale location stays. `shortTimeAgo` on the location timestamp tells the user: "Location from 6h ago." After 24h stale, consider dimming the display.
- International distance → Show in miles for US locale, km for metric locales. Use `Locale.current.measurementSystem`.

---

## 7. Feature 6: StandBy Mode Optimization

### Emotional Value
StandBy transforms the iPhone into a nightstand display when charging in landscape. It's the first and last thing couples see each day. A beautiful partner widget on the nightstand creates "ambient intimacy" during the most emotionally significant moments — waking up and falling asleep.

### Architecture

**No new code needed — this is purely a design and layout concern.** StandBy uses the same WidgetKit families (`systemSmall`, `systemMedium`) rendered in landscape on a full-screen canvas. The key differences:

1. **Rendering context changes.** StandBy may use `.vibrant` rendering mode (similar to lock screen). Our existing `widgetRenderingMode` handling in the widget views already adapts to this.
2. **Always-On Display.** On iPhone 14 Pro+ and 15 Pro+, StandBy can show widgets dimmed but always visible. Our widget should look good in both full brightness and dimmed states.
3. **Two-column layout.** StandBy shows two `systemSmall` widgets side-by-side, or one `systemMedium` full-width. Users could pair our status widget with our days-together widget, or pair our widget with Apple's clock widget.

### Design Adjustments

**For StandBy context specifically:**
- Ensure text is large enough to read from nightstand distance (~2-3 feet). The current `systemSmall` partner name uses `.headline` (17pt) — might need `.title3` (20pt) for StandBy readability.
- Ensure the status emoji is the dominant visual element — it should be recognizable from across the room.
- In `.vibrant` mode, ensure sufficient contrast. Test white-on-translucent readability.
- Consider a "night mode" variant: when the system clock is between 10PM-7AM, the widget could emphasize 😴 sleeping status or show "Goodnight 💛" if both partners set sleeping status.

### Implementation Plan

**Modified files:**
- `widgets.swift` — Audit all widget views for StandBy readability. Increase font sizes if needed. Add `@Environment(\.widgetContentMargins)` awareness for StandBy's different margins. Test all three rendering modes.
- Potentially add a `FondStandBySmallView` variant with larger type, or use conditional sizing based on `widgetRenderingMode`.

**Testing checklist:**
- [ ] systemSmall in StandBy left column
- [ ] systemSmall in StandBy right column
- [ ] systemMedium full-width in StandBy
- [ ] Always-On Display dimmed state (iPhone 14 Pro+)
- [ ] Night Shift / True Tone color temperature
- [ ] vibrant rendering mode contrast
- [ ] Text readable from 2-3 feet

**No Firestore changes. No Cloud Function changes. No new files likely needed.**

---

## 8. Feature 7: Heartbeat Snapshot Sharing

### Emotional Value
"When I start to miss my boyfriend's touch I hold the heartbeat next to my chest." This is the most intimate digital signal possible. A point-in-time heart rate snapshot sent from your wrist to your partner's phone/watch is the closest thing to physical presence that software can provide.

### Architecture

**HealthKit read on watchOS → WatchConnectivity → existing push pipeline.**

This is a point-in-time snapshot, not a continuous stream. One HealthKit query, one number, one Firestore write, one push. Cost is identical to sending a status update.

**Data flow:**
1. User taps "Send Heartbeat ❤️" on watchOS app
2. Watch queries HealthKit: `HKQuantityType(.heartRate)`, most recent sample
3. Watch sends `["action": "heartbeat", "bpm": 72]` via `WCSession.sendMessage`/`transferUserInfo`
4. `WatchSyncManager` on iPhone receives → `FirebaseManager.sendHeartbeat(uid:connectionId:bpm:)`
5. Encrypts `{"bpm": 72}` → writes to `users/{uid}/encryptedHeartbeat` + appends to history + calls `notifyPartner(type: "heartbeat")`
6. Partner receives push → Firestore listener fires → decrypts → writes bpm to App Group → widget shows "❤️ 72 bpm"
7. Partner's watch also receives via `updateApplicationContext`

### HealthKit Integration

**Permissions:** Request HealthKit authorization for `HKQuantityType(.heartRate)` read-only. This is a watchOS-only permission (the iPhone app doesn't need HealthKit). The permission prompt appears only when the user first taps "Send Heartbeat" — not on app install.

**Query:** Most recent heart rate sample within the last 10 minutes:
```swift
let type = HKQuantityType(.heartRate)
let predicate = HKQuery.predicateForSamples(
    withStart: Date().addingTimeInterval(-600),
    end: Date(), options: .strictEndDate
)
let descriptor = HKSampleQueryDescriptor(
    predicates: [.quantitySample(type: type, predicate: predicate)],
    sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
    limit: 1
)
let results = try await descriptor.result(for: healthStore)
let bpm = Int(results.first?.quantity.doubleValue(for: .count().unitDivided(by: .minute())) ?? 0)
```

**Fallback if no recent sample:** Show "No recent heart rate. Try checking your pulse." The watch needs to have recorded a heart rate recently (typically happens automatically every few minutes when worn). We don't trigger a manual heart rate measurement — that's a different HealthKit API with more invasive permissions.

### Partner Display

**Widget:** `accessoryCircular` with animated heart + bpm number. `systemSmall` with heart icon, bpm number, partner name, "just now" timestamp.

**In-app:** On ConnectedView, show a small heart rate pill below the partner card when a recent heartbeat has been received: "❤️ 72 bpm — 3m ago". Fades after 30 minutes (heartbeat is ephemeral, not persistent state).

**Watch:** Partner's watch shows "❤️ 72 bpm" in the connected view. Haptic when received — not a standard notification haptic, but the `WKInterfaceDevice.play(.heartbeat)` pattern if available, or `.notification` otherwise.

### Implementation Plan

**New files:**
- `watchkitapp Watch App/HeartbeatManager.swift` — Wraps HealthKit query. Handles permission. Returns latest bpm.
- `Views/HeartbeatPill.swift` — Small display component for ConnectedView showing received heartbeat.

**Modified files:**
- `WatchDataStore.swift` — Add `sendHeartbeat()` method. Queries HealthKit → sends via WCSession.
- `WatchConnectedView.swift` — Add "Send Heartbeat ❤️" button alongside "Thinking of You" button.
- `WatchSyncManager.swift` — Handle `["action": "heartbeat", "bpm": Int]` messages from watch.
- `FirebaseManager.swift` — New method `sendHeartbeat(uid:connectionId:bpm:)`.
- `ConnectedView.swift` — Add `HeartbeatPill` to partner card when recent heartbeat exists.
- `FondConstants.swift` — New App Group keys (defined above).
- `widgets.swift` — Heartbeat display in applicable widget views.
- `watchkitapp Watch App/Info.plist` — Add `NSHealthShareUsageDescription`.

**Privacy:**
- Heart rate is biometric data. It's encrypted before Firestore — Firebase never sees it.
- HealthKit permission is watch-only. The iPhone app never requests HealthKit.
- No heart rate history stored on server. The `encryptedHeartbeat` field is overwritten each time.
- History subcollection logs the event (type: heartbeat, encrypted bpm) for the user's own record.

**Edge cases:**
- HealthKit permission denied → "Send Heartbeat" button hidden. No degradation.
- No recent heart rate sample → Show "No recent reading" message on watch. Suggest putting watch on for a moment.
- Partner on Android (future, if ever cross-platform) → Feature simply doesn't exist. No broken UI.
- Very high/low bpm (medical outlier) → Display as-is. We're not a health app and don't interpret the data. If < 30 or > 200, could add a subtle note: "Heart rate seems unusual."

---

## 9. Build Order & Dependencies

Features are ordered by: (1) zero dependencies ship first, (2) features that modify shared infrastructure ship before features that depend on them, (3) emotional impact per engineering-hour.

```
Phase 1 — Foundation (no new infrastructure)
├── 1a. Expanded Status Vocabulary [Feature 2] ✅
│       Blocked by: nothing | Effort: ~2 hours
│
├── 1b. Days-Together Counter + Countdown [Feature 1] ✅
│       Blocked by: nothing | Effort: ~4 hours
│
└── 1c. StandBy Optimization [Feature 6]
        Design-only. Test widgets in StandBy on real device.
        Blocked by: nothing | Effort: ~1-2 hours

Phase 2 — Watch Interactivity (adds bidirectional WatchConnectivity) ✅ COMPLETE
├── 2a. One-Tap "Thinking of You" [Feature 3] ✅
│       WHY HERE: Opens the bidirectional watch channel.
│       Must ship before heartbeat because heartbeat reuses the same
│       watch→phone→Firestore pipeline this feature establishes.
│       Blocked by: Phase 1a (needs updated EntryType enum)
│       Requires: notifyPartner Cloud Function update (add "nudge" to valid types)
│       Effort: ~4 hours
│
└── 2b. Heartbeat Snapshot [Feature 7] ✅
        WHY AFTER 2a: Reuses the exact same watch→phone→Firestore
        pipeline. Only adds HealthKit query on the watch side.
        Blocked by: 2a (bidirectional WatchConnectivity must exist)
        Effort: ~3 hours

Phase 3 — New Data Sources (adds Location + Content) ✅ COMPLETE
├── 3a. Distance Widget [Feature 5] ✅
│       WHY HERE: Adds CLLocationManager dependency and a new
│       permission flow. More complex than prior phases.
│       Blocked by: Phase 1a (needs stable App Group key set)
│       Effort: ~5 hours
│
└── 3b. Daily Prompt [Feature 4] ✅
        WHY LAST: Most content-heavy feature. Requires writing/curating
        the prompt JSON. Can ship with 30 prompts and expand later.
        Blocked by: Phase 1a (needs updated EntryType enum)
        Effort: ~5 hours (code) + ongoing (content curation)
```

**Total estimated effort:** ~24-26 hours of focused development, not counting testing.

**Critical path:** Phase 1a (UserStatus expansion) and Phase 2a (bidirectional watch) are the two gating items. Everything else can be parallelized.

### Deploy Coordination

**Cloud Function update** must deploy before any clients ship Phase 2. The `notifyPartner` validation change (adding new valid types) is backward-compatible — old clients send `"status"` and `"message"` which still work. But new clients sending `"nudge"` or `"heartbeat"` will get rejected by the old function. Deploy the function update first, then ship the client.

**Firestore rules** may need a minor update for the connection doc's `anniversaryDate` field (Phase 1b). Deploy rules before client ships that feature.

---

## 10. File Inventory (New + Modified)

### New Files

| File | Target(s) | Phase | Purpose |
|------|-----------|-------|---------|
| `Shared/Models/DailyPrompt.swift` | All | 3b | Prompt data model |
| `Shared/Services/DailyPromptManager.swift` | iOS/Mac | 3b | Prompt loading, rotation, answer management |
| `Shared/Services/LocationManager.swift` | iOS/Mac | 3a | CLLocationManager wrapper, one-shot, encrypt+write |
| `Resources/DailyPrompts.json` | iOS/Mac | 3b | 365 bundled prompts |
| `Views/DailyPromptCard.swift` | iOS/Mac | 3b | Prompt UI for ConnectedView |
| `Views/HeartbeatPill.swift` | iOS/Mac | 2b | Small heartbeat display component |
| `Views/StatusPickerSheet.swift` | iOS/Mac | 1a | Grid-based status picker (replaces inline pills) |
| `watchkitapp Watch App/HeartbeatManager.swift` | watchOS | 2b | HealthKit heart rate query |
| `widgets/FondDateWidget.swift` | Widget | 1b | Days-together + countdown widget |
| `widgets/FondDistanceWidget.swift` | Widget | 3a | Distance display widget |

### Modified Files

| File | Phase(s) | Changes |
|------|----------|---------|
| `Shared/Models/UserStatus.swift` | 1a | Expand from 4 to ~16 cases, add category property |
| `Shared/Models/FondUser.swift` | All | Add new encrypted fields |
| `Shared/Models/FondMessage.swift` | 2a | Add EntryType cases: nudge, heartbeat, promptAnswer |
| `Shared/Constants/FondConstants.swift` | All | New App Group keys |
| `Shared/Services/FirebaseManager.swift` | 1b, 2a, 2b, 3a, 3b | New methods for each feature's Firestore writes |
| `Shared/Services/WatchSyncManager.swift` | 2a, 2b | Bidirectional: add receive handlers |
| `Views/ConnectedView.swift` | 1a, 1b, 2b, 3a, 3b | Status picker swap, prompt card, heartbeat pill, distance display |
| `Views/SettingsView.swift` | 1b | Anniversary + countdown date pickers |
| `Views/HistoryView.swift` | 2a, 2b, 3b | Render new entry types (nudge, heartbeat, prompt) |
| `watchkitapp Watch App/WatchDataStore.swift` | 2a, 2b | Add sendNudge(), sendHeartbeat() methods |
| `watchkitapp Watch App/Views/WatchConnectedView.swift` | 2a, 2b | Add nudge + heartbeat buttons |
| `widgets/widgets.swift` | 6 | StandBy readability tweaks |
| `widgets/widgetsBundle.swift` | 1b, 3a | Register new widgets |
| `FondApp.swift` | 3a | Location update on foreground |
| `Info.plist` | 3a | Location usage description |
| `watchkitapp Watch App/Info.plist` | 2b | HealthKit usage description |
| `functions/src/notifyPartner.ts` | 2a | Add new valid types |

---

## 11. Cloud Function Changes

### notifyPartner.ts

**Change:** Expand valid type set. Make nudge an alert notification (not silent).

```typescript
// Type validation
const validTypes = ["status", "message", "nudge", "heartbeat", "promptAnswer"];

// Notification routing
const alertTypes = ["message", "nudge"]; // Show visible notification
const isAlert = alertTypes.includes(data.type);

// Notification copy
const notificationBody = {
  message: "New message from your person 💛",
  nudge: "💛 is thinking of you",
}[data.type] || null;
```

The function remains content-blind. For nudge, we don't include the sender's name in the push payload (that would require reading encrypted data). Instead, the client-side notification handler can enrich it from local state. Or simpler: just use "Your person is thinking of you 💛" — warm and private.

**No other Cloud Function changes.** `linkUsers`, `unlinkConnection`, `expireCodes` are unaffected.

---

## 12. Firestore Rules Changes

### Connection Document — Anniversary Write

```javascript
match /connections/{connectionId} {
    // ... existing rules ...
    
    // Update: connection members can update (already permitted).
    // No rule change needed — the existing broad update rule covers anniversaryDate.
    // If we want to restrict what fields can be updated, add:
    allow update: if isSignedIn() && isConnectionMember(resource.data);
}
```

The existing rule already allows connection members to update the connection doc. Adding `anniversaryDate` requires no rule change unless we want to restrict update scope (which we should consider for hardening, but it's not blocking).

### User Document — New Fields

No rule changes needed. The existing rule allows owners to update their own doc:
```javascript
allow update: if isOwner(uid);
```

All new fields (encryptedLocation, encryptedHeartbeat, encryptedPromptAnswer, countdownDate, countdownLabel) are written by the owner to their own doc. Existing rules cover this.

---

## 13. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **UserStatus enum expansion breaks old clients** | Medium | Low | `UserStatus(rawValue:)` returns nil for unknown values. Add fallback: display raw string + default emoji. Ship server-side type validation before client update. |
| **WatchConnectivity messages lost** | Low | Medium | Use `transferUserInfo` as fallback for `sendMessage`. transferUserInfo is queued and guaranteed delivery. User sees slight delay, not data loss. |
| **Location permission denied after feature ships** | High | Low | Feature is entirely optional. If denied, distance UI hidden. All other features unaffected. No broken states. |
| **HealthKit permission denied** | High | Low | Same as location — heartbeat feature hidden, everything else works. |
| **Daily prompt content exhaustion** | Low (at 365) | Medium | Prompts loop after 365 days. Monitor analytics for the first user to hit day 366. If engagement drops, invest in more content. |
| **App Group UserDefaults growing too large** | Low | Medium | Current keys: ~8. After expansion: ~20. Each key stores a small string or number. Total size well under 1MB. Not a concern for v1. If it grows, migrate to a shared SQLite or App Group file. |
| **StandBy widget unreadable** | Medium | Low | Test on physical device at nightstand distance. Increase font sizes if needed. This is the lowest-risk feature since it's purely visual. |
| **notifyPartner rate explosion from nudge spam** | Low | Medium | Client-side 5s rate limit. Server-side rate limit is a documented future TODO. For v1, client enforcement is sufficient. Add server-side limit if abuse is detected. |
| **Multiple widgets competing for App Group writes** | Low | Low | Widgets don't write to App Group — they only read. Main app is the sole writer. No race conditions. |
| **Countdown date in partner's timezone shows wrong day** | Low | Low | Countdown dates are stored as UTC Timestamps. Display logic computes days-remaining using device local time. Both partners may see slightly different counts near midnight — acceptable. |

---

## Appendix: What We're NOT Building (and Why)

These features surfaced in the competitive research but are intentionally excluded from this plan:

| Feature | Why Not |
|---------|---------|
| **Photo sharing** | Requires Firebase Storage (new infra + cost). Deferred to a dedicated future plan. |
| **Virtual pet co-parenting** | Full game system, misaligned with Fond's intimate identity. Different product. |
| **Full quiz/assessment system** | Content operation, not a feature. 365 daily prompts covers 80% of the value. |
| **Real-time heart rate streaming** | Battery-killing on watch, expensive Firestore writes. Snapshot is sufficient. |
| **Live location tracking** | Background location is battery-intensive, privacy-hostile, and Apple gates it heavily. One-shot on app open is the right pattern. |
| **Full messaging system** | Competes with iMessage. Fond's short messages are intentionally constrained. |
| **Custom emoji / sticker creation** | Scope creep. Expanded status vocabulary covers the emotional range. Revisit in v2. |
| **Shared calendar** | Between tried this. Users defaulted to Apple Calendar. Not our fight. |
| **Shared finance tracking** | Honeydue's territory. Not aligned with Fond's emotional focus. |

---

*This document should be updated as features are implemented. Mark phases as ✅ Done when complete. If architectural decisions change during implementation, update the rationale here so future-you understands why.*
