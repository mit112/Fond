# ConnectedView Breathing Hub — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the ConnectedView home screen as a "Breathing Hub" — partner card with status atmosphere dominates, contextual smart cards surface relevant content, fixed bottom bar for status + messaging, nudge via long-press gesture.

**Architecture:** Bottom-up build — new leaf components first (`PageDotsView`, `ContextualCardView`), then modify existing components (`ConnectedPartnerCard`, `ConnectedMessageInput`), then rewire the parent (`ConnectedView`), and finally update the data layer (`ConnectedView+DataHandling`). Each task produces a compilable change.

**Tech Stack:** SwiftUI (iOS 26), `EllipticalGradient`, `TimelineView`, `.glassEffect()`, `TabView(.page)`, Firebase Firestore listeners

**Spec:** `docs/superpowers/specs/2026-03-21-connected-view-redesign.md`

---

### Task 1: Add `nudgeCooldownSeconds` constant

**Files:**
- Modify: `Fond/Fond/Shared/Constants/FondConstants.swift`

- [ ] **Step 1: Add constant**

In `FondConstants.swift`, after the existing `rateLimitSeconds` constant (line 31), add:

```swift
static let nudgeCooldownSeconds = 30
```

- [ ] **Step 2: Build to verify**

Run: Build the Fond scheme to confirm no compile errors.

- [ ] **Step 3: Commit**

```bash
git add Fond/Fond/Shared/Constants/FondConstants.swift
git commit -m "chore: add nudgeCooldownSeconds constant"
```

---

### Task 2: Create `PageDotsView`

**Files:**
- Create: `Fond/Fond/Views/PageDotsView.swift`

- [ ] **Step 1: Create the view**

```swift
//
//  PageDotsView.swift
//  Fond
//
//  Custom page indicator with variable-width active dot.
//  Active dot is a 10pt capsule tinted to match content color.
//  Inactive dots are 4pt circles.
//

import SwiftUI

struct PageDotsView: View {
    let count: Int
    let activeIndex: Int
    var activeColor: Color = FondColors.amber

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                if index == activeIndex {
                    Capsule()
                        .fill(activeColor)
                        .frame(width: 10, height: 4)
                } else {
                    Circle()
                        .fill(FondColors.textSecondary.opacity(0.15))
                        .frame(width: 4, height: 4)
                }
            }
        }
        .animation(.fondQuick, value: activeIndex)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: Build the Fond scheme. Confirm `PageDotsView` compiles.

- [ ] **Step 3: Commit**

```bash
git add Fond/Fond/Views/PageDotsView.swift
git commit -m "feat: add PageDotsView — custom page indicator"
```

---

### Task 3: Create `ContextualCardView`

**Files:**
- Create: `Fond/Fond/Views/ContextualCardView.swift`

This is the smart contextual card that surfaces the most relevant content below the partner card.

- [ ] **Step 1: Create the contextual card types and view**

```swift
//
//  ContextualCardView.swift
//  Fond
//
//  Smart contextual card that surfaces the most relevant secondary content.
//  Swipeable horizontal paging with custom page dots.
//  Card types: daily prompt, heartbeat, sent echo, nudge received, both answered.
//

import SwiftUI

// MARK: - Card Type

enum ContextualCardType: Identifiable {
    case dailyPrompt(text: String)
    case heartbeat(bpm: Int, time: Date)
    case sentEcho(message: String)
    case nudgeReceived(partnerName: String)
    case bothAnswered

    var id: String {
        switch self {
        case .dailyPrompt: "prompt"
        case .heartbeat: "heartbeat"
        case .sentEcho: "echo"
        case .nudgeReceived: "nudge"
        case .bothAnswered: "bothAnswered"
        }
    }

    var icon: String {
        switch self {
        case .dailyPrompt: "💬"
        case .heartbeat: "❤️"
        case .sentEcho: "✓"
        case .nudgeReceived: "💛"
        case .bothAnswered: "✨"
        }
    }

    var tintColor: Color {
        switch self {
        case .heartbeat: FondColors.rose
        default: FondColors.amber
        }
    }
}

// MARK: - Contextual Card View

struct ContextualCardView: View {
    let cards: [ContextualCardType]
    let onTapPrompt: () -> Void

    @State private var selectedIndex = 0

    var body: some View {
        if cards.isEmpty { EmptyView() } else {
            VStack(spacing: 6) {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        cardContent(card)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(minHeight: 70)
                .onChange(of: cards.count) { _, newCount in
                    if selectedIndex >= newCount {
                        selectedIndex = max(0, newCount - 1)
                    }
                }

                if cards.count > 1 {
                    PageDotsView(
                        count: cards.count,
                        activeIndex: selectedIndex,
                        activeColor: cards.indices.contains(selectedIndex)
                            ? cards[selectedIndex].tintColor
                            : FondColors.amber
                    )
                }
            }
        }
    }

    // MARK: - Card Content

    @ViewBuilder
    private func cardContent(_ card: ContextualCardType) -> some View {
        let tint = card.tintColor
        Button {
            handleTap(card)
        } label: {
            HStack(spacing: 10) {
                Text(card.icon)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(cardLabel(card))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .tracking(0.3)

                    Text(cardSubtitle(card))
                        .font(.callout)
                        .foregroundStyle(FondColors.text.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()

                if isTappable(card) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FondColors.textSecondary.opacity(0.15))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isTappable(card))
    }

    // MARK: - Helpers

    private func cardLabel(_ card: ContextualCardType) -> String {
        switch card {
        case .dailyPrompt: "TODAY'S QUESTION"
        case .heartbeat: "HEARTBEAT"
        case .sentEcho: "SENT"
        case .nudgeReceived: "THINKING OF YOU"
        case .bothAnswered: "ANSWERS READY"
        }
    }

    private func cardSubtitle(_ card: ContextualCardType) -> String {
        switch card {
        case .dailyPrompt(let text): text
        case .heartbeat(let bpm, let time):
            "\(bpm) bpm • \(time.shortTimeAgo)"
        case .sentEcho(let message): "You: \(message)"
        case .nudgeReceived(let name): "\(name) is thinking of you"
        case .bothAnswered: "Tap to reveal answers"
        }
    }

    private func isTappable(_ card: ContextualCardType) -> Bool {
        switch card {
        case .dailyPrompt, .bothAnswered: true
        default: false
        }
    }

    private func handleTap(_ card: ContextualCardType) {
        switch card {
        case .dailyPrompt, .bothAnswered:
            onTapPrompt()
        default:
            break
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: Build the Fond scheme. `ContextualCardView` depends on `PageDotsView` (Task 2) and `FondColors`.

- [ ] **Step 3: Commit**

```bash
git add Fond/Fond/Views/ContextualCardView.swift
git commit -m "feat: add ContextualCardView — smart contextual card with surfacing logic"
```

---

### Task 4: Redesign `ConnectedPartnerCard`

**Files:**
- Modify: `Fond/Fond/Views/ConnectedPartnerCard.swift`

Rewrite the partner card with: status atmosphere gradient, new hierarchy (status dot → emoji → name → message bubble → time ago → ambient data row → nudge hint), accessibility labels.

- [ ] **Step 1: Rewrite ConnectedPartnerCard**

Replace the entire contents of `ConnectedPartnerCard.swift` with the new design. Key changes from current:

- Add `distanceMiles: Double?`, `partnerCity: String?`, `nudgeHintVisible: Bool` parameters
- Remove `emojiBounce` parameter (bounce is now driven internally via `.animation(.fondSpring, value: partnerStatus)`)
- Status dot + label replaces the old status text under the name
- Message gets a lavender bubble background (`FondColors.bubblePartner`) with `.transition(.opacity.combined(with: .move(edge: .bottom)))` for slide-in animation
- Heartbeat pill and distance pill are merged into a single "ambient data row"
- `EllipticalGradient` overlay for status atmosphere
- Nudge hint text at bottom
- `@Environment(\.accessibilityReduceMotion)` to gate breathing animation — when true, `scaleEffect` stays at 1.0
- `.accessibilityElement(children: .combine)` with computed label
- `.accessibilityAction(named: "Send nudge")` — calls through to parent via new `onNudge` closure

**Backward compatibility:** Keep old parameters with defaults so Tasks 4-5 don't break the build:

```swift
struct ConnectedPartnerCard: View {
    let partnerName: String
    let partnerStatus: UserStatus?
    let partnerMessage: String?
    let partnerLastUpdated: Date?
    let partnerHeartbeatBpm: Int?
    let partnerHeartbeatTime: Date?
    // New parameters (defaults for backward compat, removed in Task 6)
    var distanceMiles: Double? = nil
    var partnerCity: String? = nil
    var isBreathing: Bool = false
    var nudgeHintVisible: Bool = true
    var isStale: Bool = false
    var onNudge: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}
```

**Stale-data visual treatment** — when `isStale` is true:
- Time ago label color: `FondColors.amber.opacity(0.6)` instead of `FondColors.textSecondary`
- Ambient data row opacity: `0.4`
- Status atmosphere gradient opacity: `0.05` instead of `0.10`

**No-data state** — when `partnerStatus` is nil:
- Emoji shows `"⏳"` (existing behavior)
- Status dot + label hidden
- Ambient data row hidden (natural — `distanceMiles` and `partnerHeartbeatBpm` are nil)

Full implementation: build the view body with the spec's element ordering (status dot, emoji at `.system(size: 52)`, name as `.title.bold()`, message bubble with `FondColors.bubblePartner` background in `RoundedRectangle(cornerRadius: 16)`, time ago, ambient data row, nudge hint). Add `EllipticalGradient(colors: [statusColor.opacity(isStale ? 0.05 : 0.10), .clear], center: .init(x: 0.5, y: 0.3))` overlay. Wrap in `fondCard(cornerRadius: 24)` with breathing `scaleEffect(reduceMotion ? 1.0 : (isBreathing ? 1.003 : 1.0))`. Add `.accessibilityAction(named: "Send nudge") { onNudge?() }`.

- [ ] **Step 2: Build to verify**

Build should pass — backward-compatible parameters allow old call site to work.

- [ ] **Step 3: Commit**

```bash
git add Fond/Fond/Views/ConnectedPartnerCard.swift
git commit -m "feat: redesign ConnectedPartnerCard — status atmosphere, message bubble, ambient data row"
```

---

### Task 5: Simplify `ConnectedMessageInput` to fixed bottom bar

**Files:**
- Modify: `Fond/Fond/Views/ConnectedMessageInput.swift`

Simplify to just the fixed bottom bar: status pill (left) + message input with send button (right). Remove `lastSentBadge` (moved to contextual card echo). Keep cooldown ring, char count, error feedback.

- [ ] **Step 1: Rewrite ConnectedMessageInput**

**Backward compatibility:** Keep old parameters with defaults so old call site still works:

```swift
struct ConnectedMessageInput: View {
    @Binding var messageText: String
    var myStatus: UserStatus = .available  // new, with default
    let isSending: Bool
    let sendSuccess: Bool
    let cooldownRemaining: Int
    let errorMessage: String?
    var lastSentMessage: String? = nil     // kept for compat, unused in new layout
    let onSend: () -> Void
    var onStatusTap: (() -> Void)? = nil   // new, with default
}
```

Remove `lastSentBadge` view (echo moves to contextual card).

Layout becomes:
```
VStack(spacing: 0) {
    feedbackBar  // error / char count — only when needed
    HStack(spacing: 8) {
        statusPill   // emoji + chevron, tap → onStatusTap
        inputField   // text field + send button with cooldown
    }
}
```

Status pill: `Button` with emoji (18pt) + chevron (`.caption2`, very faint), `.fondGlassInteractive(in: RoundedRectangle(cornerRadius: 16))`, with `.accessibilityLabel("Your status: \(myStatus.displayName). Double tap to change.")`.

Input field + send button: keep existing `inputRow` and `sendButton` logic. Reduce send button frame from `42pt` to `30pt`:
```swift
.frame(width: 30, height: 30)
```
And the cooldown ring overlay frame from `46pt` to `34pt`:
```swift
.frame(width: 34, height: 34)
```

- [ ] **Step 2: Build to verify**

Build should pass — backward-compatible parameters allow old call site to work.

- [ ] **Step 3: Commit**

```bash
git add Fond/Fond/Views/ConnectedMessageInput.swift
git commit -m "feat: simplify ConnectedMessageInput — status pill + compact input bar"
```

---

### Task 6: Rewire `ConnectedView` layout

**Files:**
- Modify: `Fond/Fond/Views/ConnectedView.swift`

This is the main integration task. Rewire the body to the new layout: toolbar → partner card → contextual card → fixed bottom bar. Add nudge state, contextual card state, and `TimelineView` for staleness.

- [ ] **Step 1: Add new state properties**

Add to ConnectedView's state declarations:

```swift
// MARK: - Nudge
@State private var lastNudgeTime: Date = .distantPast
@State private var nudgeHintVisible = true
@State private var nudgeScale: CGFloat = 1.0
@State private var nudgeShakeOffset: CGFloat = 0

// MARK: - Contextual Card
@State private var lastSentMessageTime: Date?
@State var lastNudgeReceivedTime: Date?
@State private var showDailyPromptSheet = false
```

- [ ] **Step 2: Rewrite the `body` property**

New layout structure:
```swift
var body: some View {
    ZStack {
        FondMeshGradient()
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }

        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Spacer(minLength: 16)

            // Partner card with nudge gesture
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                ConnectedPartnerCard(
                    partnerName: partnerName,
                    partnerStatus: partnerStatus,
                    partnerMessage: partnerMessage,
                    partnerLastUpdated: partnerLastUpdated,
                    partnerHeartbeatBpm: partnerHeartbeatBpm,
                    partnerHeartbeatTime: partnerHeartbeatTime,
                    distanceMiles: distanceMiles,
                    partnerCity: partnerCity,
                    isBreathing: isBreathing,
                    nudgeHintVisible: nudgeHintVisible,
                    isStale: isDataStale
                )
            }
            .padding(.horizontal, 24)
            .opacity(partnerDataVisible ? 1 : 0)
            .scaleEffect(partnerDataVisible ? nudgeScale : 0.95)
            .offset(x: nudgeShakeOffset)
            .onLongPressGesture(minimumDuration: 0.5) {
                sendNudge()
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }

            Spacer(minLength: 12)

            // Contextual card
            TimelineView(.periodic(from: .now, by: 10)) { _ in
                ContextualCardView(
                    cards: activeContextualCards,
                    onTapPrompt: { showDailyPromptSheet = true }
                )
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 10)

            // Fixed bottom bar
            ConnectedMessageInput(
                messageText: $messageText,
                myStatus: myStatus,
                isSending: isSending,
                sendSuccess: sendSuccess,
                cooldownRemaining: cooldownRemaining,
                errorMessage: errorMessage,
                onSend: sendMessage,
                onStatusTap: { showStatusPicker = true }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
    // sheets...
}
```

- [ ] **Step 3: Update the toolbar**

Replace the toolbar wordmark text:
```swift
Text("FOND")
    .font(.caption.weight(.medium))
    .foregroundStyle(FondColors.textSecondary.opacity(0.3))
    .tracking(1.5)
```
Keep 40pt frames on the gear and clock buttons. Keep existing `.fondGlassInteractive(in: Circle())` style.

- [ ] **Step 4: Add `@Environment(\.accessibilityReduceMotion)` and gate breathing**

Add to ConnectedView:
```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```
In `.onAppear`, gate the breathing animation:
```swift
.onAppear {
    guard !reduceMotion else { return }
    withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
        isBreathing = true
    }
}
```

- [ ] **Step 5: Add `.accessibilityAction` for nudge on partner card**

After `.onLongPressGesture`, add:
```swift
.accessibilityAction(named: "Send nudge") { sendNudge() }
```

- [ ] **Step 6: Remove old `statusIndicator`, `distancePill`, `dailyPrompt` computed properties**

These are replaced by:
- `statusIndicator` → status pill inside `ConnectedMessageInput`
- `distancePill` → ambient data row inside `ConnectedPartnerCard`
- `dailyPrompt` → contextual card

- [ ] **Step 6b: Remove `emojiBounce` state and its usage**

Delete `@State var emojiBounce = false` from ConnectedView. In `ConnectedView+DataHandling.swift`, remove the `emojiBounce` toggle block (lines 209-216 of current file) that sets `emojiBounce = true` and resets it after 0.4s. The bounce is now handled internally by `ConnectedPartnerCard` via `.animation(.fondSpring, value: partnerStatus)`.

- [ ] **Step 6c: Remove backward-compat defaults from component call sites**

Now that `ConnectedView` passes the new parameters to `ConnectedPartnerCard` and `ConnectedMessageInput`, the default values added in Tasks 4-5 can optionally be removed. This is a cleanup step — leave the defaults if you prefer, or remove them for explicitness.

- [ ] **Step 7: Add nudge action method**

```swift
private func sendNudge() {
    let now = Date()
    guard now.timeIntervalSince(lastNudgeTime) >= Double(FondConstants.nudgeCooldownSeconds) else {
        FondHaptics.error()
        withAnimation(.fondQuick) {
            nudgeShakeOffset = 4
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.fondQuick) { nudgeShakeOffset = -4 }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.fondQuick) { nudgeShakeOffset = 4 }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.fondQuick) { nudgeShakeOffset = 0 }
        }
        return
    }

    guard let uid = authManager.currentUser?.uid,
          let connectionId else { return }

    lastNudgeTime = now
    FondHaptics.messageSent()
    nudgeHintVisible = false

    withAnimation(.fondQuick) { nudgeScale = 1.02 }
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.fondQuick) { nudgeScale = 1.0 }
    }

    Task {
        do {
            try await FirebaseManager.shared.sendNudge(uid: uid, connectionId: connectionId)
        } catch {
            logger.error("Nudge failed: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 8: Add `activeContextualCards` computed property**

```swift
private var activeContextualCards: [ContextualCardType] {
    var cards: [ContextualCardType] = []
    let now = Date()

    // Priority 1: Nudge received (ephemeral)
    if let nudgeTime = lastNudgeReceivedTime,
       now.timeIntervalSince(nudgeTime) < 30 {
        cards.append(.nudgeReceived(partnerName: partnerName))
    }

    // Priority 2: Fresh heartbeat
    if let bpm = partnerHeartbeatBpm,
       let time = partnerHeartbeatTime,
       now.timeIntervalSince(time) < 1800 {
        cards.append(.heartbeat(bpm: bpm, time: time))
    }

    // Priority 3: Both answered prompt
    let pm = DailyPromptManager.shared
    if pm.isSubmitted && pm.partnerAnswer != nil {
        cards.append(.bothAnswered)
    }
    // Priority 4: Unanswered prompt
    else if let prompt = pm.todaysPrompt, !pm.isSubmitted {
        cards.append(.dailyPrompt(text: prompt.text))
    }

    // Priority 5: Sent message echo
    if let sentTime = lastSentMessageTime,
       now.timeIntervalSince(sentTime) < 60,
       let msg = lastSentMessage {
        cards.append(.sentEcho(message: msg))
    }

    return cards
}
```

- [ ] **Step 9: Add `isDataStale` computed property**

```swift
private var isDataStale: Bool {
    guard let lastUpdated = partnerLastUpdated else { return false }
    return Date().timeIntervalSince(lastUpdated) > 3600
}
```

- [ ] **Step 10: Add daily prompt sheet**

Add to the `.sheet` modifiers:
```swift
.sheet(isPresented: $showDailyPromptSheet) {
    if let uid = authManager.currentUser?.uid, let cid = connectionId {
        DailyPromptCard(partnerName: partnerName, uid: uid, connectionId: cid)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}
```

- [ ] **Step 11: Update `sendMessage()` to set `lastSentMessageTime`**

After the successful send (where `sendSuccess = true`), add:
```swift
lastSentMessageTime = Date()
```

- [ ] **Step 12: Reset nudge hint on scene phase**

In `handleScenePhaseChange`, add:
```swift
nudgeHintVisible = true
```

- [ ] **Step 13: Add a logger**

At the top of the file (after imports), add:
```swift
import os
private let logger = Logger(subsystem: "com.mitsheth.Fond", category: "ConnectedView")
```

- [ ] **Step 14: Build and verify**

Run: Build the Fond scheme. All four components should compile together. Fix any parameter mismatches.

- [ ] **Step 15: Commit**

```bash
git add Fond/Fond/Views/ConnectedView.swift
git commit -m "feat: rewire ConnectedView — breathing hub layout with nudge gesture and contextual cards"
```

---

### Task 7: Wire nudge-received data flow

**Files:**
- Modify: `Fond/Fond/Shared/Services/FirebaseManager.swift`
- Modify: `Fond/Fond/Views/ConnectedView+DataHandling.swift`

- [ ] **Step 1: Update `sendNudge()` in `FirebaseManager.swift` to write `lastNudge` timestamp**

Read `FirebaseManager.swift` and find the `sendNudge(uid:connectionId:)` method (around line 267). After the existing writes, add a write of `lastNudge: FieldValue.serverTimestamp()` to the user's Firestore document so the partner's listener can detect it:

```swift
// In sendNudge(), after writing to history, also update the user doc:
try await db.collection(FondConstants.usersCollection)
    .document(uid)
    .updateData(["lastNudge": FieldValue.serverTimestamp()])
```

- [ ] **Step 2: Add `lastNudge` to `PartnerUpdate` struct**

Find the `PartnerUpdate` struct in `FirebaseManager.swift`. Add:
```swift
let lastNudge: Date?
```

In the `listenToPartner()` method, parse the field from the Firestore document:
```swift
let lastNudge = (data["lastNudge"] as? Timestamp)?.dateValue()
```
Pass it to the `PartnerUpdate` initializer.

- [ ] **Step 3: Parse nudge in `ConnectedView+DataHandling`**

In `applyPartnerUpdate()`, after the heartbeat handling block, add:
```swift
// Nudge received
if let nudgeTime = update.lastNudge,
   nudgeTime != lastNudgeReceivedTime {
    withAnimation(.fondQuick) {
        lastNudgeReceivedTime = nudgeTime
    }
    FondHaptics.partnerUpdated()
}
```

Also remove the `emojiBounce` toggle block (lines ~209-216) since bounce is now handled by the card's `.animation(.fondSpring, value: partnerStatus)`.

- [ ] **Step 4: Build and verify**

Run: Build the Fond scheme. Verify the nudge-received data flow compiles end-to-end.

- [ ] **Step 5: Commit**

```bash
git add Fond/Fond/Shared/Services/FirebaseManager.swift Fond/Fond/Views/ConnectedView+DataHandling.swift
git commit -m "feat: wire nudge-received data flow — Firestore timestamp + listener parsing"
```

---

### Task 8: Build, run, and visual verification

**Files:** None (verification only)

- [ ] **Step 1: Build the full project**

Build the Fond scheme for iOS Simulator. Fix any remaining compile errors.

- [ ] **Step 2: Run on simulator**

Launch on iPhone 16 simulator. Verify:
- Mesh gradient background renders
- Toolbar shows settings gear, "FOND" wordmark, history clock
- Partner card shows with status atmosphere gradient
- Contextual card shows daily prompt
- Bottom bar has status pill + message input
- Long-press on partner card triggers nudge haptic (if simulator supports)

- [ ] **Step 3: Check state variations**

- Verify "no message" state (partner card without bubble)
- Verify contextual card hides when no content available

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "fix: resolve any remaining build issues from breathing hub redesign"
```

Only commit if there were actual fixes needed. Skip if Task 7 built clean.
