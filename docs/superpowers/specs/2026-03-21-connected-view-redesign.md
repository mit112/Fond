# ConnectedView Redesign — Breathing Hub

**Date:** 2026-03-21
**Status:** Approved
**Scope:** `ConnectedView.swift`, `ConnectedPartnerCard.swift`, `ConnectedMessageInput.swift`, new `ContextualCardView.swift`, new `PageDotsView.swift`

## Summary

Redesign the ConnectedView home screen as a "Breathing Hub" — partner presence dominates 60% of the screen with status-colored atmosphere, a smart contextual card surfaces the most relevant secondary content, and a fixed bottom bar provides status + message input. Nudge is a long-press gesture on the partner card.

Driven by research (see `~/Documents/design-assets/Fond/research/CONTEXT-REPORT.md`) showing ambient awareness is the primary mechanism for digital intimacy, and that "presence without pressure" is the core emotional promise.

## Design Principles

1. **Partner presence first** — Their name, status, and message are the emotional center. Everything else is secondary.
2. **Ambient over active** — The app rewards a glance, not a session. Status atmosphere communicates mood before you read a word.
3. **Nothing hidden** — All features have a visible presence. No gesture-only functionality except nudge (which has a hint label).
4. **Calm technology** — Require the smallest possible amount of attention. Inform and encalm.

## Screen Layout

```
┌─────────────────────────────────┐
│ [⚙]       FOND            [🕐] │  Toolbar (nearly invisible)
│                                 │
│  ┌───────────────────────────┐  │
│  │ ● Available               │  │  Status dot + label
│  │                           │  │
│  │         😊                │  │  .system(size: 52)
│  │        Alex               │  │  .title.bold()
│  │                           │  │
│  │   ┌─────────────────┐    │  │
│  │   │ "miss you today" │    │  │  Message bubble (lavender tint)
│  │   └─────────────────┘    │  │
│  │       5 min ago           │  │
│  │                           │  │
│  │   📍 12 mi Seattle │ ❤️ 72 │  │  Ambient data row
│  │                           │  │
│  │     hold to nudge         │  │  Gesture hint (very faint)
│  └───────────────────────────┘  │  ← Status color atmosphere
│                                 │
│  ┌───────────────────────────┐  │
│  │ 💬 TODAY'S QUESTION    [•••]│  │  Contextual card (swipeable)
│  │ What made you smile today? │  │
│  └───────────────────────────┘  │
│                                 │
│  [😊 ›]  [Say something... [↑]] │  Fixed bottom: status + input
└─────────────────────────────────┘
```

## Component Specifications

### 1. Toolbar

- **Left:** Settings gear — 40pt touch target frame, visual circle can be 34pt, `fondGlassInteractive(in: Circle())`
- **Center:** "FOND" wordmark — `.caption.weight(.medium)`, `FondColors.textSecondary.opacity(0.3)`, `.tracking(1.5)`. Subtle brand presence, not invisible.
- **Right:** History clock — same sizing and style as gear
- **Behavior:** Static, no scroll interaction

### 2. Partner Card (60% of screen)

**Layout:** Centered VStack inside a glass card (`fondCard(cornerRadius: 24)`)

**Elements (top to bottom):**
1. **Status indicator** — 7pt colored dot + status label (e.g., "Available" in status color). Compact inline layout.
2. **Emoji** — `.system(size: 52)` (intentional bump from current 48pt for more visual weight). Scale bounce on update via `.animation(.fondSpring, value: partnerStatus)`.
3. **Name** — `.title.bold()`, `FondColors.text`, `.tracking(-0.5)`. Uses semantic text style for Dynamic Type support.
4. **Message bubble** — Only when partner has sent a message. Background: `FondColors.bubblePartner` in a `RoundedRectangle(cornerRadius: 16, style: .continuous)`. Padding: `.horizontal(16), .vertical(10)`. Text: `.body`, `FondColors.text.opacity(0.7)`. Max 3 lines. **This is a new visual element** — the current design shows message as plain text without a bubble.
5. **Time ago** — `.caption`, `FondColors.textSecondary`, `.contentTransition(.numericText())`
6. **Ambient data row** — Horizontal: distance (amber pin icon + miles + city name) | 1pt separator | heartbeat (rose heart + bpm). Only shows items that have data. `.caption`, `.monospacedDigit()`.
7. **Nudge hint** — "hold to nudge" — `.caption2`, `FondColors.textSecondary.opacity(0.15)`. Fades out after first successful nudge per foreground cycle (uses `scenePhase == .active` to reset).

**Status Atmosphere:**
- `EllipticalGradient` overlay using the partner's `statusColor` at 10% opacity
- `EllipticalGradient(colors: [statusColor.opacity(0.10), .clear], center: .init(x: 0.5, y: 0.3))`
- Animates with `.fondSpring` when status changes — color cross-fades

**Breathing animation:** `scaleEffect(isBreathing ? 1.003 : 1.0)` with 4s easeInOut repeating (existing pattern). Respects `@Environment(\.accessibilityReduceMotion)` — disabled when true.

**Nudge gesture:**
- `.onLongPressGesture(minimumDuration: 0.5)` on the card
- **Independent rate limit:** 30-second cooldown tracked by `@State private var lastNudgeTime: Date = .distantPast`. Separate from message/status rate limit.
- **Success path:** `FondHaptics.messageSent()`, card scales to 1.02 with `.fondQuick`, amber tint flash on the atmosphere gradient (opacity pulses 0.10 → 0.25 → 0.10)
- **Cooldown path:** `FondHaptics.error()`, card shakes (horizontal offset ±4pt, 3 cycles, `.fondQuick`)
- **Error path:** Same as cooldown — `FondHaptics.error()` + shake. Error is logged via `os.Logger`, not shown in UI (nudge is fire-and-forget).
- Sends nudge via `FirebaseManager.shared.sendNudge()`
- **Accessibility:** `.accessibilityAction(named: "Send nudge")` added to card for VoiceOver users

### 3. Contextual Card

**New component:** `ContextualCardView`

**Layout:** Horizontal `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))`. Minimum height 70pt, flexible up to content. Tap expands to sheet.

**Custom page dots:** New `PageDotsView` — active dot is wider (10pt capsule) tinted to match the active card color, inactive dots are 4pt circles at `FondColors.textSecondary.opacity(0.15)`. This is a custom view since `.page` indicator cannot be styled this way.

**Card types and surfacing priority:**

| Card | Surfaces When | Tint | Icon | Tap Action |
|------|--------------|------|------|------------|
| Daily Prompt | Always (if unanswered) | Amber | 💬 | Present `DailyPromptCard` in `.medium` sheet |
| Fresh Heartbeat | BPM received < 30min ago | Rose | ❤️ | No-op (data is already visible in card + ambient row) |
| Sent Message Echo | After sending, for ~60s | Amber | ✓ | None (auto-dismisses) |
| Nudge Received | Partner nudged you | Amber | 💛 | None (auto-dismisses after 30s) |
| Both Answered Prompt | Both partners answered | Amber | ✨ | Present `DailyPromptCard` in `.medium` sheet (shows both-answers view) |

**Surfacing logic (priority order):**
1. If nudge received in last 30s → show nudge card (highest priority — ephemeral, time-sensitive)
2. If heartbeat < 30min old → show heartbeat card
3. If both answered prompt → show reveal card
4. If daily prompt unanswered → show prompt card
5. If message just sent (< 60s) → show echo card
6. Fallback: hide contextual card entirely if no content (reclaim space for partner card)

**Ephemeral card state:**
- `@State private var lastSentMessageTime: Date?` — tracks when echo should auto-dismiss
- `@State private var lastNudgeReceivedTime: Date?` — tracks when nudge card should auto-dismiss
- Use `TimelineView(.periodic(from: .now, by: 10))` to re-evaluate which cards are active (handles auto-dismiss of echo and nudge cards, and staleness checks)

**Swipe:** Horizontal swipe between available cards. Only cards with active content appear.

### 4. Nudge-Received Data Flow

When partner sends a nudge, the data arrives via two paths:

1. **Push notification fast path:** `PushManager` receives FCM data payload with `type: "nudge"` → writes `lastPartnerNudgeTime` to App Group UserDefaults → `ConnectedView` observes via `scenePhase` change or Firestore listener
2. **Firestore listener fallback:** The existing partner document listener in `ConnectedView+DataHandling.swift` reads a `lastNudge` timestamp field → updates `@State var lastNudgeReceivedTime: Date?`

The contextual card checks `lastNudgeReceivedTime` and shows the nudge card if it's within the last 30 seconds.

**New state in ConnectedView:**
```swift
@State var lastNudgeReceivedTime: Date?
```

**New field parsed in `handlePartnerUpdate()`:**
```swift
if let nudgeTimestamp = data["lastNudge"] as? Timestamp {
    let nudgeDate = nudgeTimestamp.dateValue()
    if nudgeDate != lastNudgeReceivedTime {
        lastNudgeReceivedTime = nudgeDate
        FondHaptics.partnerUpdated()
    }
}
```

### 5. Fixed Bottom Bar

**Layout:** HStack with 8pt gap

**My Status Pill:**
- Emoji (18pt) + chevron (`.caption2`, very faint)
- `fondGlassInteractive(in: RoundedRectangle(cornerRadius: 16))`
- Tap → `StatusPickerSheet` (existing, no changes needed)
- The emoji alone communicates current status — users learn the emoji mapping quickly from the status picker. No text label needed in the compact pill.

**Message Input:**
- TextField "Say something..." — `.callout` placeholder
- Background: glass surface with 18pt corner radius (matching existing `ConnectedMessageInput` style)
- Send button: 30pt circle, amber-tinted glass, arrow-up icon
- Submit via keyboard or button tap
- Cooldown ring overlay (existing pattern, keep as-is)
- `.submitLabel(.send)`

**Character count:** Appears above the input bar when > 70% of max length (existing behavior from `ConnectedMessageInput`)

### 6. Mesh Gradient Background

No changes to `FondMeshGradient`. Existing 3x3 grid, 6s breathing cycle, warm amber/lavender/cream palette.

## State Variations

### No Message State
When partner hasn't sent a message:
- Message bubble is hidden
- Card content shifts up slightly (VStack spacing handles this naturally)
- Time ago moves directly under name
- Card feels more spacious

### No Partner Data Yet
When first connected, before any data arrives:
- Emoji shows hourglass (⏳)
- Name shows partner name from pairing
- Status label hidden
- Ambient data row hidden
- Contextual card shows daily prompt

### Stale Data (> 1 hour)
- Time ago label gets slightly more prominent (`FondColors.textSecondary` → `FondColors.amber.opacity(0.6)`)
- Ambient data row values show with reduced opacity (0.4)
- Status atmosphere gradient fades to 5% opacity
- **Detection:** `TimelineView(.periodic(from: .now, by: 60))` wraps the partner card, re-evaluating staleness every minute by comparing `partnerLastUpdated` to `Date.now`

## Accessibility

- **Reduce Motion:** Breathing animation on partner card and mesh gradient animation both check `@Environment(\.accessibilityReduceMotion)` and disable when true. Status atmosphere color changes still animate (they are functional, not decorative).
- **VoiceOver:** Partner card has `.accessibilityElement(children: .combine)` with a computed label: "Alex, available, miss you today, 5 minutes ago, 12 miles away in Seattle, 72 beats per minute". Nudge gesture has `.accessibilityAction(named: "Send nudge")`.
- **Dynamic Type:** All text uses semantic SwiftUI text styles (`.title`, `.body`, `.caption`, `.caption2`) that scale with user preferences. Emoji sizes are fixed (they don't need to scale).
- **Status pill:** `.accessibilityLabel("Your status: Available. Double tap to change.")` on the status pill.

## Animations

| Trigger | Animation | Spec |
|---------|-----------|------|
| Partner data arrives | Card content fade + scale | `.fondSpring`, opacity 0→1, scale 0.95→1 |
| Status changes | Atmosphere color cross-fade | `.fondSpring`, `EllipticalGradient` color transition |
| Emoji changes | Bounce | Scale 1→1.2→1, `.fondSpring` |
| Message arrives | Bubble slides in | `.fondSpring`, from bottom, combined opacity+move |
| Nudge sent (success) | Card pulse + tint flash | Scale 1→1.02→1, `.fondQuick`, atmosphere opacity pulse |
| Nudge sent (cooldown) | Card shake | Horizontal offset ±4pt, 3 cycles, `.fondQuick` |
| Contextual card swap | Page transition | `.tabViewStyle(.page)` default |
| Sent message echo appears | Slide up | `.fondQuick`, opacity + move from bottom |

## Files Changed

| File | Change |
|------|--------|
| `ConnectedView.swift` | New layout structure, nudge gesture + rate limit state, contextual card integration, `TimelineView` for staleness |
| `ConnectedPartnerCard.swift` | Status atmosphere (`EllipticalGradient`), new hierarchy (name hero, message bubble), ambient data row, nudge hint, accessibility labels |
| `ConnectedMessageInput.swift` | Simplified to just the fixed bottom bar (status pill + message input). Status pill is new; previous full-width status indicator removed. |
| `ContextualCardView.swift` | **New** — horizontal paging `TabView` with smart card surfacing logic |
| `PageDotsView.swift` | **New** — custom page indicator with variable-width active dot |
| `ConnectedView+DataHandling.swift` | Parse `lastNudge` timestamp from partner document, manage contextual card ephemeral state |

## Files NOT Changed

- `FondTheme.swift` — All existing modifiers reused as-is
- `FondColors.swift` — All existing colors reused as-is (status atmosphere uses existing `UserStatus.statusColor`)
- `StatusPickerSheet.swift` — No changes
- `HistoryView.swift` — No changes
- `SettingsView.swift` — No changes
- `DailyPromptCard.swift` — Reused inside contextual card's sheet expansion

## Out of Scope

- Widget redesign (separate effort)
- Watch app changes
- New features (photo sharing, etc.)
- Onboarding flow changes
- Settings or history view changes
