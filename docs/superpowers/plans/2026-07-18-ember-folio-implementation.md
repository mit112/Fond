# Ember Folio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Fond's Breathing Hub with the approved Ember Folio two-faced keepsake card, then carry the same visual language into widgets and watchOS without changing product behavior, storage, crypto, or backend contracts.

**Architecture:** Keep `ConnectedView` as the real-time orchestration boundary, but move rendering into pure value-model views: `NowFaceView`, `TogetherFaceView`, `TogetherThreadView`, and a generic `CardTurnContainer`. Put palette, typography, spacing, card chrome, glass controls, and motion math in shared theme files; isolate Firestore pagination behind a protocol-backed `TogetherThreadStore`. Widgets and watchOS consume the same shared semantic palette/type tokens while retaining their existing data pipelines.

**Tech Stack:** Swift 5 / SwiftUI on Xcode 27, Observation, Swift Testing, XCTest UI tests, WidgetKit, AppIntents, WatchKit, Firebase Firestore, OSLog, Fraunces Variable and Newsreader Variable under SIL OFL 1.1.

## Global Constraints

- Structure, IA, feature set, Firestore schema, Cloud Functions, App Group keys, notification pipeline, and E2E crypto are locked and unchanged.
- The build must run against the iOS 27, iPadOS 27, macOS 27, and watchOS 27 SDKs; do not change the repository's existing 26.0 deployment floors in this visual pass.
- Liquid Glass appears only on the floating toolbar and compose/send controls. Never apply glass to the card, question, answer field, thread, widget content, or text.
- Use `.regular`; do not use `.clear` in the connected experience. Never stack or overlap glass surfaces.
- Use one semantic amber family only. Status hues appear only in the three dot contexts specified by the visual spec.
- Preserve `UserStatus` and `FondMessage.EntryType` raw values exactly.
- Preserve all encrypted-field names and all App Group/Keychain identifiers exactly.
- Every interactive target is at least 44 × 44 pt.
- Preserve Dynamic Type, Bold Text, VoiceOver, Reduce Motion, Reduce Transparency, Increase Contrast, Differentiate Without Color, and reduced-luminance behavior.
- Use `Logger`, never `print()`.
- Do not introduce a snapshot-test dependency. Use pure Swift tests, debug design-gallery UI tests, Widget previews, and simulator screenshots.
- Do not add AI attribution to commits. Each task ends in one imperative, logical commit.

---

## File map

### Create

- `Fond/Fond/Resources/Fonts/Fraunces[SOFT,WONK,opsz,wght].ttf` — bundled display font.
- `Fond/Fond/Resources/Fonts/Newsreader[opsz,wght].ttf` — bundled reading font.
- `Fond/Fond/Resources/Fonts/OFL-Fraunces.txt` — Fraunces license.
- `Fond/Fond/Resources/Fonts/OFL-Newsreader.txt` — Newsreader license.
- `Fond/Fond/Shared/Theme/FondTypography.swift` — variable-font construction and type tokens.
- `Fond/Fond/Shared/Theme/FondSpacing.swift` — spacing and geometry constants.
- `Fond/Fond/Shared/Theme/CardTurn.swift` — face enum, pure motion math, and generic card-turn container.
- `Fond/Fond/Views/NowFaceView.swift` — pure Now face.
- `Fond/Fond/Views/TogetherMoment.swift` — decrypted presentation model and payload parser.
- `Fond/Fond/Views/TogetherThreadStore.swift` — protocol-backed history pagination and grouping.
- `Fond/Fond/Views/TogetherThreadView.swift` — day labels and four moment styles.
- `Fond/Fond/Views/TogetherFaceView.swift` — Today masthead, answer states, spread, and thread.
- `Fond/widgets/FondWidgetStyle.swift` — shared widget rendering-mode style.
- `Fond/Fond/Views/Design/FondDesignGallery.swift` — debug-only authenticated-state-free visual harness.
- `Fond/FondTests/FondPaletteTests.swift` — exact color/contrast tests.
- `Fond/FondTests/CardTurnMathTests.swift` — drag/settle tests.
- `Fond/FondTests/RelationshipDateSummaryTests.swift` — date-line tests.
- `Fond/FondTests/TogetherMomentBuilderTests.swift` — history parsing/grouping tests.
- `Fond/FondUITests/EmberFolioUITests.swift` — launch-argument visual and gesture smoke tests.

### Modify

- `Fond/Fond/Shared/Theme/FondColors.swift` — semantic Ember Folio palette and status groups.
- `Fond/Fond/Shared/Theme/FondTheme.swift` — flat field, opaque card, glass controls, fallbacks, motion.
- `Fond/Fond/Shared/Services/DailyPromptManager.swift` — prompt lookup by stored prompt ID.
- `Fond/Fond/Views/ConnectedView.swift` — two-face shell and shared controls.
- `Fond/Fond/Views/ConnectedView+DataHandling.swift` — initialize/refresh relationship summary and thread.
- `Fond/Fond/Views/ConnectedMessageInput.swift` — opaque plate inside one glass compose cluster.
- `Fond/Fond/ContentView.swift` — debug-only design gallery route.
- `Fond/widgets/widgets.swift` — ambient keepsake widget families.
- `Fond/widgets/FondDateWidget.swift` — Ember Folio date widget styling.
- `Fond/widgets/FondDistanceWidget.swift` — Ember Folio distance widget styling.
- `Fond/watchkitapp Watch App/Views/WatchConnectedView.swift` — watch face hierarchy and controls.
- `Fond/Fond/Info.plist`, `Fond/widgets/Info.plist`, `Fond/watchkitapp Watch App/Info.plist` — font registration.
- `Fond/Fond.xcodeproj/project.pbxproj` — font membership for app/widget/watch targets.

### Retire after integration

- `Fond/Fond/Views/ConnectedPartnerCard.swift` — superseded by `NowFaceView`.
- `Fond/Fond/Views/ContextualCardView.swift` — its content moves into Today/thread.
- `Fond/Fond/Views/DailyPromptCard.swift` — its behavior moves into `TogetherFaceView`.
- `Fond/Fond/Views/HistoryView.swift` — its data and presentation move into `TogetherThreadStore/View`.

Keep `PageDotsView.swift`, but change its geometry to the approved 7 pt/4 pt two-dot indicator.

---

### Task 1: Install the Ember Folio token and font foundation

**Files:**
- Create: font and license files listed in the file map
- Create: `Fond/Fond/Shared/Theme/FondTypography.swift`
- Create: `Fond/Fond/Shared/Theme/FondSpacing.swift`
- Create: `Fond/FondTests/FondPaletteTests.swift`
- Modify: `Fond/Fond/Shared/Theme/FondColors.swift`
- Modify: three target `Info.plist` files and `Fond/Fond.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `FondPalette`, `FondRGB`, `FondColors.field`, `.keepsake`, `.ink`, `.inkSecondary`, `.rule`, `.amber`, `.controlPlate`, `.controlFallback`, `.sendForeground`, `.shadow`.
- Produces: `FondType.partnerName`, `.question`, `.momentQuestion`, `.pullQuote`, `.voice`, `.body`, `.control`, `.metadata`, `.eyebrow`.
- Produces: `FondSpacing` and `FondGeometry` constants used by every later task.

- [ ] **Step 1: Add failing palette and font-registration tests**

```swift
import CoreGraphics
import Testing
@testable import Fond

struct FondPaletteTests {
    @Test func exactPaletteValues() {
        #expect(FondPalette.fieldLight.hex == 0xEEE7DC)
        #expect(FondPalette.fieldDark.hex == 0x191715)
        #expect(FondPalette.keepsakeLight.hex == 0xFFF9EE)
        #expect(FondPalette.keepsakeDark.hex == 0x24201C)
        #expect(FondPalette.amberLight.hex == 0xA85F00)
        #expect(FondPalette.amberDark.hex == 0xD68A1F)
    }

    @Test func textContrastMeetsAA() {
        #expect(FondRGB.contrast(FondPalette.inkDark, FondPalette.keepsakeDark) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.inkLight, FondPalette.keepsakeLight) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.inkSecondaryDark, FondPalette.keepsakeDark) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.inkSecondaryLight, FondPalette.keepsakeLight) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.amberDark, FondPalette.keepsakeDark) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.amberLight, FondPalette.keepsakeLight) >= 4.5)
    }

    @Test func controlContrastSurvivesMaterialChanges() {
        #expect(FondRGB.contrast(FondPalette.inkDark, FondPalette.controlPlateDark) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.inkLight, FondPalette.controlPlateLight) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.sendForegroundDark, FondPalette.amberDark) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.sendForegroundLight, FondPalette.amberLight) >= 4.5)
    }
}
```

- [ ] **Step 2: Run the tests and confirm the missing-token failure**

Run:

```bash
xcodebuild -project Fond/Fond.xcodeproj -scheme Fond -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:FondTests/FondPaletteTests test
```

Expected: compilation fails because `FondPalette` and `FondRGB` do not exist.

- [ ] **Step 3: Download the exact OFL font binaries and licenses**

Run:

```bash
mkdir -p Fond/Fond/Resources/Fonts
curl -L 'https://raw.githubusercontent.com/google/fonts/main/ofl/fraunces/Fraunces%5BSOFT%2CWONK%2Copsz%2Cwght%5D.ttf' -o 'Fond/Fond/Resources/Fonts/Fraunces[SOFT,WONK,opsz,wght].ttf'
curl -L 'https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/Newsreader%5Bopsz%2Cwght%5D.ttf' -o 'Fond/Fond/Resources/Fonts/Newsreader[opsz,wght].ttf'
curl -L 'https://raw.githubusercontent.com/google/fonts/main/ofl/fraunces/OFL.txt' -o Fond/Fond/Resources/Fonts/OFL-Fraunces.txt
curl -L 'https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/OFL.txt' -o Fond/Fond/Resources/Fonts/OFL-Newsreader.txt
```

Verify:

```bash
file Fond/Fond/Resources/Fonts/*.ttf
shasum -a 256 Fond/Fond/Resources/Fonts/*
```

Expected: both `.ttf` files report TrueType/OpenType font data; both license files and both fonts receive nonempty SHA-256 hashes.

- [ ] **Step 4: Implement exact RGB values and contrast math**

```swift
struct FondRGB: Sendable, Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    init(hex: UInt32) {
        red = CGFloat((hex >> 16) & 0xFF) / 255
        green = CGFloat((hex >> 8) & 0xFF) / 255
        blue = CGFloat(hex & 0xFF) / 255
    }

    var hex: UInt32 {
        UInt32((red * 255).rounded()) << 16
            | UInt32((green * 255).rounded()) << 8
            | UInt32((blue * 255).rounded())
    }

    static func contrast(_ first: Self, _ second: Self) -> Double {
        func luminance(_ color: Self) -> Double {
            func channel(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
        }
        let values = [luminance(first), luminance(second)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }
}

enum FondPalette {
    static let fieldLight = FondRGB(hex: 0xEEE7DC)
    static let fieldDark = FondRGB(hex: 0x191715)
    static let keepsakeLight = FondRGB(hex: 0xFFF9EE)
    static let keepsakeDark = FondRGB(hex: 0x24201C)
    static let inkLight = FondRGB(hex: 0x26211C)
    static let inkDark = FondRGB(hex: 0xF7EFE3)
    static let inkSecondaryLight = FondRGB(hex: 0x665C52)
    static let inkSecondaryDark = FondRGB(hex: 0xBDB2A5)
    static let amberLight = FondRGB(hex: 0xA85F00)
    static let amberDark = FondRGB(hex: 0xD68A1F)
    static let controlPlateLight = keepsakeLight
    static let controlPlateDark = FondRGB(hex: 0x312B24)
    static let sendForegroundLight = keepsakeLight
    static let sendForegroundDark = FondRGB(hex: 0x211B14)
}
```

Replace old connected-surface semantics in `FondColors` with adaptive colors derived from these values. Keep temporary deprecated aliases only where onboarding/settings still compile; mark them for removal after Task 9. Preserve all 16 status meanings while limiting the dot palette to the four approved status colors plus the existing amber: green = available/happy/calm/exercising; coral = busy/stressed/excited; lavender = away/sad/working/driving; indigo = sleeping; amber = eating/thinkingOfYou/missYou/lovingYou. The adjacent word carries the exact status, so the reduced dot palette does not remove information.

- [ ] **Step 5: Implement spacing and variable-font tokens**

```swift
enum FondSpacing {
    static let one: CGFloat = 4
    static let two: CGFloat = 8
    static let three: CGFloat = 12
    static let four: CGFloat = 16
    static let five: CGFloat = 24
    static let six: CGFloat = 32
    static let seven: CGFloat = 48
    static let eight: CGFloat = 64
}

enum FondGeometry {
    static let cardMarginCompact: CGFloat = 20
    static let cardMarginRegular: CGFloat = 28
    static let cardCornerRadius: CGFloat = 34
    static let controlHeight: CGFloat = 52
    static let minimumTarget: CGFloat = 44
    static let contentMaxWidth: CGFloat = 640
}
```

In `FondTypography.swift`, create a `FondVariableFont.make(name:size:relativeTo:axes:)` helper. On UIKit platforms, use `UIFontDescriptor.AttributeName.variation` plus `UIFontMetrics(forTextStyle:)`; on AppKit, use `NSFontDescriptor.AttributeName.variation`; fall back to `.system(_:design:.serif)` if the bundled font cannot load. Define `FondType` with the exact sizes and relative text styles from the approved spec.

```swift
enum FondType {
    static var partnerName: Font { FondVariableFont.make(name: "Fraunces", size: 58, relativeTo: .largeTitle, axes: ["opsz": 72, "SOFT": 35, "WONK": 1, "wght": 550]) }
    static var question: Font { FondVariableFont.make(name: "Fraunces", size: 34, relativeTo: .title, axes: ["opsz": 48, "SOFT": 28, "WONK": 1, "wght": 520]) }
    static var momentQuestion: Font { FondVariableFont.make(name: "Fraunces", size: 21, relativeTo: .title3, axes: ["opsz": 28, "SOFT": 22, "wght": 500]) }
    static var pullQuote: Font { FondVariableFont.make(name: "Newsreader", size: 25, relativeTo: .title2, axes: ["opsz": 30, "wght": 400]) }
    static var voice: Font { FondVariableFont.make(name: "Newsreader", size: 18, relativeTo: .body, axes: ["opsz": 20, "wght": 400]) }
    static let body = Font.body
    static let control = Font.body.weight(.semibold)
    static let metadata = Font.caption.weight(.medium).monospacedDigit()
    static let eyebrow = Font.caption2.weight(.semibold)
}
```

- [ ] **Step 6: Register fonts in all three UI bundles**

Add `UIAppFonts` arrays containing the two exact TTF filenames to the app, widget, and watch `Info.plist` files. Add both resource paths to the widget and watch synchronized-target membership lists in `project.pbxproj`; the main app receives them through its synchronized root group.

- [ ] **Step 7: Run token tests and all-target compile checks**

Run the palette test command from Step 2, then:

```bash
xcodebuild -project Fond/Fond.xcodeproj -scheme Fond -sdk iphonesimulator -configuration Debug build
xcodebuild -project Fond/Fond.xcodeproj -scheme widgetsExtension -sdk iphonesimulator -configuration Debug build
xcodebuild -project Fond/Fond.xcodeproj -scheme 'watchkitapp Watch App' -sdk watchsimulator -configuration Debug build
```

Expected: tests pass; all three builds end with `BUILD SUCCEEDED`; build logs contain no missing-font-resource warning.

- [ ] **Step 8: Commit**

```bash
git add Fond/Fond/Resources/Fonts Fond/Fond/Shared/Theme Fond/FondTests/FondPaletteTests.swift Fond/Fond/Info.plist Fond/widgets/Info.plist 'Fond/watchkitapp Watch App/Info.plist' Fond/Fond.xcodeproj/project.pbxproj
git commit -m "feat: add Ember Folio design tokens"
```

---

### Task 2: Build opaque card, control, and turn primitives

**Files:**
- Create: `Fond/Fond/Shared/Theme/CardTurn.swift`
- Create: `Fond/FondTests/CardTurnMathTests.swift`
- Modify: `Fond/Fond/Shared/Theme/FondTheme.swift`
- Modify: `Fond/Fond/Views/PageDotsView.swift`

**Interfaces:**
- Produces: `enum FondFace { case now, together }`.
- Produces: `CardTurnMath.progress`, `.destination`, `.angle`.
- Produces: `CardTurnContainer(face:front:back:)` with an interruptible horizontal drag.
- Produces: `.fondKeepsakeCard()`, `.fondFloatingControl()`, `.fondControlPlate()`, `.fondSendControl()`.

- [ ] **Step 1: Write failing motion-math tests**

```swift
import Testing
@testable import Fond

struct CardTurnMathTests {
    @Test func nowFaceTracksLeftDrag() {
        #expect(CardTurnMath.progress(translation: -176, width: 400, from: .now) == 0.5)
        #expect(CardTurnMath.angle(progress: 0.5, from: .now) == 90)
    }

    @Test func togetherFaceTracksRightDrag() {
        #expect(CardTurnMath.progress(translation: 176, width: 400, from: .together) == 0.5)
        #expect(CardTurnMath.angle(progress: 0.5, from: .together) == 90)
    }

    @Test func thresholdAndVelocityCommit() {
        #expect(CardTurnMath.destination(progress: 0.41, velocity: 0, from: .now) == .now)
        #expect(CardTurnMath.destination(progress: 0.42, velocity: 0, from: .now) == .together)
        #expect(CardTurnMath.destination(progress: 0.1, velocity: -451, from: .now) == .together)
        #expect(CardTurnMath.destination(progress: 0.1, velocity: 451, from: .together) == .now)
    }
}
```

- [ ] **Step 2: Run and confirm the missing-type failure**

Run the Fond test command with `-only-testing:FondTests/CardTurnMathTests`. Expected: compilation fails because `CardTurnMath` is undefined.

- [ ] **Step 3: Implement the pure turn state**

```swift
enum FondFace: Int, CaseIterable, Sendable { case now, together }

enum CardTurnMath {
    static let widthFactor: CGFloat = 0.88
    static let commitProgress: CGFloat = 0.42
    static let commitVelocity: CGFloat = 450

    static func progress(translation: CGFloat, width: CGFloat, from face: FondFace) -> CGFloat {
        guard width > 0 else { return 0 }
        let directed = face == .now ? -translation : translation
        return min(max(directed / (width * widthFactor), 0), 1)
    }

    static func angle(progress: CGFloat, from face: FondFace) -> Double {
        face == .now ? Double(progress * 180) : Double(180 - progress * 180)
    }

    static func destination(progress: CGFloat, velocity: CGFloat, from face: FondFace) -> FondFace {
        let velocityCommits = face == .now ? velocity < -commitVelocity : velocity > commitVelocity
        guard progress >= commitProgress || velocityCommits else { return face }
        return face == .now ? .together : .now
    }
}
```

- [ ] **Step 4: Implement the theme modifiers and accessibility fallbacks**

Replace `FondMeshGradient` in the connected path with `FondField`, a flat `FondColors.field` view. Delete the content-card `.clear` branch. `FondKeepsakeModifier` must use an opaque fill, 1.25 pt amber stroke, 0.5 pt inset highlight, 34 pt radius, and appearance-aware shadow. `FondFloatingControlModifier` and `FondSendControlModifier` must read `accessibilityReduceTransparency`; when true, render `fondControlFallback` plus a rule instead of glass.

Use `.regular.interactive()` for toolbar/compose and `.regular.tint(FondColors.amber).interactive()` for send. Do not apply one modifier on top of another.

- [ ] **Step 5: Implement the generic card container**

`CardTurnContainer` accepts a `Binding<FondFace>`, `reduceMotion`, and two view builders. Render front and back in one `ZStack`, rotate the back by 180°, hide each face after it passes 90°, and apply perspective `1 / 850`. Use `DragGesture(minimumDistance: 8)` with horizontal-intent lock; on release, settle with `Animation.interpolatingSpring(mass: 1, stiffness: 330, damping: 32, initialVelocity:)`. Under Reduce Motion, swap faces with a 90 ms out/120 ms in cross-fade and no rotation.

At the 90° commit point, fire one selection haptic. Mark the nonvisible face `accessibilityHidden(true)` throughout the gesture; move VoiceOver focus to the destination face only after the spring settles.

Add a 7 pt amber edge peek on the hidden-face side. Update `PageDotsView` to exactly two circular dots: active 7 pt amber, inactive 4 pt secondary, 5 pt spacing.

- [ ] **Step 6: Run motion tests and compile**

Expected: `CardTurnMathTests` passes and the Fond scheme builds. Manually preview 0°, 67°, 90°, and 180° in `#Preview` variants; no mirrored text is visible.

- [ ] **Step 7: Commit**

```bash
git add Fond/Fond/Shared/Theme/CardTurn.swift Fond/Fond/Shared/Theme/FondTheme.swift Fond/Fond/Views/PageDotsView.swift Fond/FondTests/CardTurnMathTests.swift
git commit -m "feat: add keepsake card turn primitives"
```

---

### Task 3: Build the Now face as a pure presence view

**Files:**
- Create: `Fond/Fond/Views/NowFaceView.swift`
- Create: `Fond/FondTests/RelationshipDateSummaryTests.swift`

**Interfaces:**
- Produces: `NowFaceModel` value type.
- Produces: `RelationshipDateSummary.make(anniversary:countdown:label:now:) -> String?`.
- Produces: `NowFaceView(model:isBreathing:onNudge:)`.

- [ ] **Step 1: Write date-summary tests**

```swift
import Foundation
import Testing
@testable import Fond

struct RelationshipDateSummaryTests {
    let calendar = Calendar(identifier: .gregorian)

    @Test func combinesDaysAndCountdown() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let anniversary = calendar.date(byAdding: .day, value: -412, to: now)!
        let countdown = calendar.date(byAdding: .day, value: 18, to: now)!
        #expect(RelationshipDateSummary.make(anniversary: anniversary, countdown: countdown, label: "Lisbon", now: now, calendar: calendar) == "412 days together · 18 until Lisbon")
    }

    @Test func omitsExpiredCountdown() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let countdown = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(RelationshipDateSummary.make(anniversary: nil, countdown: countdown, label: "Lisbon", now: now, calendar: calendar) == nil)
    }
}
```

- [ ] **Step 2: Run and confirm the missing-summary failure**

Run only `RelationshipDateSummaryTests`. Expected: compilation fails because the summary type is absent.

- [ ] **Step 3: Implement the value model and summary**

```swift
struct NowFaceModel: Sendable {
    let partnerName: String
    let status: UserStatus?
    let message: String?
    let lastUpdated: Date?
    let heartbeatBpm: Int?
    let heartbeatTime: Date?
    let distanceMiles: Double?
    let relationshipLine: String?
    let isStale: Bool
}
```

Implement `RelationshipDateSummary` with calendar start-of-day math, singular/plural handling, trimmed countdown label, and no negative countdown.

- [ ] **Step 4: Implement the three-block Now layout**

Use a leading-aligned grid inside `ScrollView`:

1. 8 pt status dot + lowercase word, 58 pt Fraunces name, relationship line.
2. 2 pt amber leading rule, 25 pt Newsreader message, `from <name> · <time>`.
3. top rule and available facts in the order `distance · bpm · updated`.

Do not show emoji, bubbles, status atmosphere, colored status text, heartbeat animation, or a nudge instruction. Make the identity block a `Button` with `.buttonStyle(.plain)`, a 44 pt minimum target, accessibility label `Send a nudge to <name>`, and one named accessibility action. Stale data changes the freshness copy to `last seen …`; it never lowers essential content opacity.

- [ ] **Step 5: Run tests, preview both appearances, and commit**

```bash
git add Fond/Fond/Views/NowFaceView.swift Fond/FondTests/RelationshipDateSummaryTests.swift
git commit -m "feat: build the Ember Folio Now face"
```

---

### Task 4: Model and load the Together thread

**Files:**
- Create: `Fond/Fond/Views/TogetherMoment.swift`
- Create: `Fond/Fond/Views/TogetherThreadStore.swift`
- Create: `Fond/FondTests/TogetherMomentBuilderTests.swift`
- Modify: `Fond/Fond/Shared/Services/DailyPromptManager.swift`

**Interfaces:**
- Produces: `TogetherMoment`, `TogetherDayGroup`, `TogetherMomentBuilder`.
- Produces: `HistoryProviding.nextPage(connectionId:) async throws -> HistoryPage` and `.reset()`.
- Produces: `@MainActor @Observable final class TogetherThreadStore`.
- Produces: `DailyPromptManager.promptText(forID:) -> String?`.

- [ ] **Step 1: Write history parsing tests with deterministic ciphertext substitutes**

Create entries for message, status, nudge, heartbeat JSON, and two `promptAnswer` JSON payloads sharing `promptId = "p001"`. Inject a decrypt closure that returns plaintext unchanged.

```swift
@Test func buildsEditorialMomentsAndPairsAnswers() {
    let now = Date(timeIntervalSince1970: 1_767_225_600)
    let fixtures = [
        FondMessage(id: "m1", authorUid: "me", type: .message, encryptedPayload: "Miss you", timestamp: now),
        FondMessage(id: "s1", authorUid: "partner", type: .status, encryptedPayload: "sleeping", timestamp: now.addingTimeInterval(1)),
        FondMessage(id: "n1", authorUid: "me", type: .nudge, encryptedPayload: "💛", timestamp: now.addingTimeInterval(2)),
        FondMessage(id: "h1", authorUid: "partner", type: .heartbeat, encryptedPayload: "{\"bpm\":72}", timestamp: now.addingTimeInterval(3)),
        FondMessage(id: "p1", authorUid: "me", type: .promptAnswer, encryptedPayload: "{\"promptId\":\"p001\",\"answer\":\"The walk home\"}", timestamp: now.addingTimeInterval(4)),
        FondMessage(id: "p2", authorUid: "partner", type: .promptAnswer, encryptedPayload: "{\"promptId\":\"p001\",\"answer\":\"Morning coffee\"}", timestamp: now.addingTimeInterval(5)),
    ]
    let moments = TogetherMomentBuilder.build(
        entries: fixtures,
        myUid: "me",
        decrypt: { $0 },
        promptText: { $0 == "p001" ? "What ordinary moment would you keep?" : nil }
    )
    #expect(moments.contains { $0.kind == .message(text: "Miss you", author: .me) })
    #expect(moments.contains { $0.kind == .status(status: .sleeping, label: "Sleeping", author: .partner) })
    #expect(moments.contains { $0.kind == .nudge(author: .me) })
    #expect(moments.contains { $0.kind == .heartbeat(bpm: 72, author: .partner) })
    #expect(moments.contains { $0.kind == .answeredQuestion(question: "What ordinary moment would you keep?", myAnswer: "The walk home", partnerAnswer: "Morning coffee") })
}
```

Add a second test proving malformed encrypted payloads become a dignified `.unavailable` moment instead of crashing or displaying ciphertext.

- [ ] **Step 2: Run and confirm the missing-builder failure**

Run only `TogetherMomentBuilderTests`. Expected: compilation fails because the presentation model does not exist.

- [ ] **Step 3: Implement the presentation model and builder**

```swift
struct TogetherMoment: Identifiable, Equatable, Sendable {
    enum Author: Equatable, Sendable { case me, partner }
    enum Kind: Equatable, Sendable {
        case message(text: String, author: Author)
        case status(status: UserStatus?, label: String, author: Author)
        case nudge(author: Author)
        case heartbeat(bpm: Int?, author: Author)
        case answeredQuestion(question: String, myAnswer: String?, partnerAnswer: String?)
        case unavailable
    }
    let id: String
    let timestamp: Date
    let kind: Kind
}

struct TogetherDayGroup: Identifiable, Equatable, Sendable {
    let day: Date
    let moments: [TogetherMoment]
    var id: Date { day }
}
```

Decode heartbeat and prompt-answer JSON with private `Codable` payload structs. Group prompt answers by `promptId`; emit one answered-question moment at the newer timestamp. Sort newest-first for the Together document. Preserve unknown status display using `UserStatus.displayInfo(forRawValue:)`.

- [ ] **Step 4: Encapsulate Firestore pagination behind a protocol**

```swift
struct HistoryPage: Sendable {
    let entries: [FondMessage]
    let hasMore: Bool
}

@MainActor
protocol HistoryProviding: AnyObject {
    func reset()
    func nextPage(connectionId: String) async throws -> HistoryPage
}
```

`FirebaseHistoryProvider` privately retains `DocumentSnapshot?` and calls the existing `FirebaseManager.fetchHistory`. `TogetherThreadStore` exposes `moments`, `isLoading`, `isLoadingMore`, `hasMore`, and `errorMessage`; it accepts a provider, `myUid`, decrypt closure, and prompt lookup closure. `loadInitial` resets first; `loadMore` appends and deduplicates by `FondMessage.id` before rebuilding moments.

- [ ] **Step 5: Add prompt lookup without exposing the prompt array**

```swift
func promptText(forID id: String) -> String? {
    allPrompts.first(where: { $0.id == id })?.text
}
```

- [ ] **Step 6: Run builder tests and commit**

```bash
git add Fond/Fond/Views/TogetherMoment.swift Fond/Fond/Views/TogetherThreadStore.swift Fond/FondTests/TogetherMomentBuilderTests.swift Fond/Fond/Shared/Services/DailyPromptManager.swift
git commit -m "feat: model the Together moments thread"
```

---

### Task 5: Build the Together ritual and thread views

**Files:**
- Create: `Fond/Fond/Views/TogetherThreadView.swift`
- Create: `Fond/Fond/Views/TogetherFaceView.swift`

**Interfaces:**
- Consumes: `TogetherMoment`, `TogetherThreadStore`, `FondType`, `FondSpacing`.
- Produces: `TodayRitualState` and `TogetherFaceView(state:moments:hasMore:onAnswer:onLoadMore:)`.

- [ ] **Step 1: Define a previewable ritual state**

```swift
struct TodayRitualState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case unanswered
        case waiting(myAnswer: String)
        case revealed(myAnswer: String, partnerAnswer: String)
    }
    let question: String
    let partnerName: String
    let phase: Phase
    let isSubmitting: Bool
    let errorMessage: String?
}
```

- [ ] **Step 2: Implement the four thread moment styles**

`TogetherThreadView` groups moments by local calendar day. Day headers use `FondType.eyebrow` plus one trailing rule. Message moments use Newsreader and a 2 pt amber leading rule for partner or neutral trailing rule for me. Nudge moments are centered `◉` metadata. Status moments show only a 6 pt status dot plus text. Answered questions use Fraunces question text and the two-voice spread with no container fill. Heartbeat moments use a neutral `heart` symbol and metadata; rose is prohibited.

Use `LazyVStack`, stable IDs, and a `Load earlier moments` text button when `hasMore` is true. Empty copy is exactly `Answer today's question to start your story.`

- [ ] **Step 3: Implement Today before-answer and waiting states**

`TogetherFaceView` renders `TODAY`, the 34 pt Fraunces question, then:

- `.unanswered`: 48 pt opaque answer row, 10 pt radius, 1 pt amber leading rule, multiline field, and a 44 pt send target.
- `.waiting`: the user's Newsreader answer and `Maya hasn't answered yet.` in metadata.
- error: primary-readable error text plus `Try again`; never rose-only.

The answer control is opaque content, not glass.

- [ ] **Step 4: Implement the spread reveal**

For `.revealed`, use `ViewThatFits` to choose a two-column spread or stacked spread. Divide voices with one `fondRule`. Animate mask from center plus y 6 → 0 and opacity 0 → 1 over 240 ms with `.timingCurve(0.22, 1, 0.36, 1)` and 70 ms partner delay. Under Reduce Motion, use simultaneous 120 ms opacity only.

- [ ] **Step 5: Add light/dark and Dynamic Type previews, compile, and commit**

Provide previews for unanswered, waiting, revealed, empty thread, and mixed thread at default and accessibilityExtraExtraExtraLarge.

```bash
git add Fond/Fond/Views/TogetherFaceView.swift Fond/Fond/Views/TogetherThreadView.swift
git commit -m "feat: build the Together ritual and thread"
```

---

### Task 6: Integrate the two-faced connected shell and shared controls

**Files:**
- Modify: `Fond/Fond/Views/ConnectedView.swift`
- Modify: `Fond/Fond/Views/ConnectedView+DataHandling.swift`
- Modify: `Fond/Fond/Views/ConnectedMessageInput.swift`
- Delete: superseded view files listed in the file map

**Interfaces:**
- Consumes: all Tasks 1–5 interfaces.
- Preserves: existing `ConnectedView(authManager:onDisconnect:)` public initializer and every Firebase action method.

- [ ] **Step 1: Replace transient sheet/card state with two-face state**

Add:

```swift
@State private var activeFace: FondFace = .now
@State private var threadStore: TogetherThreadStore?
@State private var promptManager = DailyPromptManager.shared
@State private var relationshipLine: String?
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

Remove `showHistory`, `showDailyPromptSheet`, `activeContextualCards`, and long-press nudge state. Keep settings and status-picker sheets.

- [ ] **Step 2: Build the shell in locked altitude order**

Use a `ZStack`: flat field, card-turn container, floating toolbar, two-dot indicator, compose cluster. Constrain card width to 640 pt and use 20/28 pt margins by horizontal size class. The toolbar contains gear, the opaque `Now · Together` plate, and a thread shortcut. The thread shortcut sets `activeFace = .together` and exposes accessibility label `Show Together thread`.

Construct `NowFaceModel` from existing partner state and App Group relationship dates. Construct `TodayRitualState` from `DailyPromptManager`. Pass existing `sendNudge`, `sendMessage`, and `setStatus` closures unchanged.

- [ ] **Step 3: Initialize thread state after connection identity is known**

After `connectionId` and current UID load, create `TogetherThreadStore(provider: FirebaseHistoryProvider(), myUid: uid, decrypt: EncryptionManager.shared.decryptOrNil, promptText: DailyPromptManager.shared.promptText)` and call `loadInitial(connectionId:)`. Refresh the thread after a successful message, status, nudge, or prompt-answer action, and after the existing partner listener receives a new status/message/nudge/prompt update, so both sides appear without changing the listener contract.

- [ ] **Step 4: Rebuild compose as one control layer**

`ConnectedMessageInput` becomes one `GlassEffectContainer` containing an untinted regular compose capsule and a sibling tinted send circle. Status and text live on `fondControlPlate`. Keep cooldown ring, character count, error recovery, submit label, 100-character cap, and 5-second rate limit. Replace emoji status control with 10 pt status dot plus accessibility text. Disabled send removes amber tint and stays at least 70% visual strength.

- [ ] **Step 5: Implement breathing and nudge truthfully**

The card breathes 1.000 → 1.003 over 5.6 seconds only when Reduce Motion is off, Low Power Mode is off, and no drag is active. Nudge is a tap on the Now identity block. Success pulses the amber edge for 120 ms and fires one light haptic; cooldown provides one resistance spring and error haptic, not a four-step shake.

- [ ] **Step 6: Delete superseded views, build, and commit**

Run the Fond build and tests. Confirm no references remain to `ConnectedPartnerCard`, `ContextualCardView`, `DailyPromptCard`, or `HistoryView`, then delete those files.

```bash
git add -A Fond/Fond/Views Fond/Fond/Shared/Services/DailyPromptManager.swift
git commit -m "feat: integrate the Ember Folio connected experience"
```

---

### Task 7: Redesign the full widget family as ambient keepsakes

**Files:**
- Create: `Fond/widgets/FondWidgetStyle.swift`
- Modify: `Fond/widgets/widgets.swift`
- Modify: `Fond/widgets/FondDateWidget.swift`
- Modify: `Fond/widgets/FondDistanceWidget.swift`

**Interfaces:**
- Produces: `FondWidgetStyle(renderingMode:)`, `WidgetStatusDot`, `WidgetKeepsakeBackground`.
- Preserves: all widget kinds, intents, App Group reads, timelines, relevance, push handler, and supported families.

- [ ] **Step 1: Implement rendering-mode semantics once**

```swift
struct FondWidgetStyle {
    let renderingMode: WidgetRenderingMode
    var primary: Color { renderingMode == .fullColor ? FondColors.ink : .primary }
    var secondary: Color { renderingMode == .fullColor ? FondColors.inkSecondary : .secondary }
    var background: Color { renderingMode == .fullColor ? FondColors.keepsake : .clear }
    var showsAuthoredEdge: Bool { renderingMode == .fullColor }
}
```

Full-color widgets use opaque keepsake fill plus 1 pt amber inset edge. Accented/vibrant widgets let WidgetKit replace the background. Mark only the status dot and single voice rule accentable. Never render emoji as the anchor.

- [ ] **Step 2: Rebuild the primary presence widget families**

- Inline: `Maya · available · 6m`.
- Circular: first grapheme in Fraunces, 6 pt dot, full accessibility label.
- Rectangular: `Maya · available`, then one-line message.
- Small: status line, 30 pt name, two-line Newsreader message, freshness footer.
- Medium: 38/62 asymmetric split with name/status left and message/signals right, separated by one amber rule.

Use `ViewThatFits` for long names and omit metadata before shrinking the partner name below its minimum legible scale.

- [ ] **Step 3: Bring date and distance widgets into the same language**

Keep their information architecture and relevance unchanged. Replace rounded/emoji hero treatments with the shared opaque background, amber rule, Fraunces primary value/name, SF metadata, and rendering-mode grouping. In reduced luminance, remove shadow/edge and drop tertiary copy.

- [ ] **Step 4: Verify all widget appearances**

Add previews for fullColor, accented, vibrant, small, medium, all accessory families, connected, stale, missing-message, and not-connected entries. Build `widgetsExtension` and inspect iPhone 17 Pro Home/Lock Screen, iPad, StandBy landscape, and watch Smart Stack previews.

- [ ] **Step 5: Commit**

```bash
git add Fond/widgets
git commit -m "feat: redesign Fond widgets as ambient keepsakes"
```

---

### Task 8: Adapt watchOS, iPadOS, and macOS behavior

**Files:**
- Modify: `Fond/watchkitapp Watch App/Views/WatchConnectedView.swift`
- Modify: `Fond/Fond/Views/ConnectedView.swift`
- Modify: `Fond/Fond/FondApp.swift` if menu commands are defined at the app scene

**Interfaces:**
- Preserves: `WatchDataStore`, HealthKit heartbeat flow, WatchConnectivity, and existing command actions.

- [ ] **Step 1: Rebuild the watch connected hierarchy**

Replace the emoji hero and gradient with the dark keepsake surface: status dot/word, 22 pt Fraunces name, one-line Newsreader message, freshness. Keep scrolling. Nudge and heartbeat remain 48 pt glass buttons below content; nudge is amber, heartbeat regular. Replace `DispatchQueue.main.asyncAfter` with `Task.sleep`, remove repeating pulse/bounce, and use Logger for failures already surfaced by the data store.

- [ ] **Step 2: Preserve Smart Stack and Always On behavior**

Verify the widget extension's watch family uses the compact hierarchy and relevance provider. Under `isLuminanceReduced`, remove edge/shadow and omit the message before reducing name/status.

- [ ] **Step 3: Add regular-width and keyboard behavior**

Keep one centered card at 560–640 pt on iPad/macOS. Do not split faces into columns. Add commands: ⌘1 Now, ⌘2 Together, ⌘Return send. Pointer hover affects glass control response only. On macOS, cap card at 680 pt and let field margins grow.

- [ ] **Step 4: Build platform targets and commit**

```bash
xcodebuild -project Fond/Fond.xcodeproj -scheme Fond -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=27.0' build
xcodebuild -project Fond/Fond.xcodeproj -scheme Fond -destination 'platform=macOS' build
xcodebuild -project Fond/Fond.xcodeproj -scheme 'watchkitapp Watch App' -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=27.0' build
```

Expected: all three end in `BUILD SUCCEEDED`.

```bash
git add Fond/Fond/Views/ConnectedView.swift Fond/Fond/FondApp.swift 'Fond/watchkitapp Watch App/Views/WatchConnectedView.swift'
git commit -m "feat: adapt Ember Folio across Apple platforms"
```

---

### Task 9: Add the design gallery and perform the final accessibility/visual gate

**Files:**
- Create: `Fond/Fond/Views/Design/FondDesignGallery.swift`
- Create: `Fond/FondUITests/EmberFolioUITests.swift`
- Modify: `Fond/Fond/ContentView.swift`
- Modify: `Fond/Fond/Shared/Theme/FondColors.swift` and `FondTheme.swift` only to remove temporary compatibility aliases after all call sites migrate
- Update: `docs/superpowers/specs/2026-07-18-fond-ember-folio-visual-system-design.md` implementation status

**Interfaces:**
- Produces: debug launch argument `-FondDesignGallery` and optional `-FondGalleryAppearance dark|light`.
- Produces: stable accessibility identifiers `fond.toolbar`, `fond.card`, `fond.face.now`, `fond.face.together`, `fond.compose`, `fond.send`.

- [ ] **Step 1: Add an authenticated-state-free debug gallery**

Under `#if DEBUG`, route `ContentView` to `FondDesignGallery` when launch arguments contain `-FondDesignGallery`. The gallery uses fixed Maya/Lisbon data and local Together moments; it performs no Firebase, Keychain, App Group, location, or notification writes. Include controls to show Now, Together unanswered, Together revealed, mid-turn 67°, stale, empty, long-name, and AX5 fixtures.

- [ ] **Step 2: Add UI smoke tests**

```swift
@MainActor
final class EmberFolioUITests: XCTestCase {
    func testTurnsFromNowToTogether() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FondDesignGallery", "-FondGalleryAppearance", "dark"]
        app.launch()
        XCTAssertTrue(app.otherElements["fond.face.now"].waitForExistence(timeout: 3))
        app.otherElements["fond.card"].swipeLeft()
        XCTAssertTrue(app.otherElements["fond.face.together"].waitForExistence(timeout: 2))
    }

    func testPrimaryTargetsExist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FondDesignGallery", "-FondGalleryAppearance", "light"]
        app.launch()
        XCTAssertTrue(app.otherElements["fond.toolbar"].exists)
        XCTAssertTrue(app.otherElements["fond.compose"].exists)
        XCTAssertTrue(app.buttons["fond.send"].exists)
    }
}
```

- [ ] **Step 3: Run automated verification**

```bash
xcodebuild -project Fond/Fond.xcodeproj -scheme Fond -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test
xcodebuild -project Fond/Fond.xcodeproj -scheme widgetsExtension -sdk iphonesimulator -configuration Debug build
xcodebuild -project Fond/Fond.xcodeproj -scheme 'watchkitapp Watch App' -sdk watchsimulator -configuration Debug build
```

Expected: all tests pass and all targets build with 0 errors. Investigate and eliminate new warnings caused by this work.

- [ ] **Step 4: Perform the manual accessibility matrix**

On iPhone 17 Pro and iPad Pro 13-inch simulators, capture Now/Together in light and dark plus one mid-turn frame. Repeat with:

- Dynamic Type default, XXXL, and AX5;
- Reduce Motion;
- Reduce Transparency;
- Increase Contrast;
- Differentiate Without Color;
- Bold Text;
- iOS 27 Liquid Glass appearance/clarity at both endpoints;
- landscape and Split View on iPad;
- VoiceOver rotor order: toolbar → visible face → compose, with hidden face absent.

Acceptance: no clipped name/question/answer; no mirrored content; no content glass; no status color outside approved dots; all control text stays ≥4.5:1 against its opaque plate; every target is ≥44 pt.

- [ ] **Step 5: Remove compatibility design APIs**

Run:

```bash
rg -n 'FondMeshGradient|fondCard\(|FondColors\.(lavender|rose|bubbleMine|bubblePartner)|glassEffect\(\.clear' Fond --glob '*.swift'
```

Expected in the connected/widget/watch paths: no matches. Onboarding may retain a separately justified background only if it is outside this connected-experience scope; content must still not use `.clear` glass. Remove unused legacy aliases from `FondColors` and `FondTheme` once all target builds remain green.

- [ ] **Step 6: Mark the visual spec implemented and commit**

```bash
git add Fond/Fond Fond/FondTests Fond/FondUITests docs/superpowers/specs/2026-07-18-fond-ember-folio-visual-system-design.md
git commit -m "test: verify the Ember Folio experience"
```

---

## Final handoff gate

Implementation is complete only when Tasks 1–9 are checked, the full `Fond` test action passes on iPhone 17 Pro iOS 27, widget/watch schemes build, the iPad/macOS builds pass, and the manual accessibility matrix has evidence screenshots. Do not treat compilation alone as visual approval; Mit must review the final simulator captures before the redesign branch is merged.
