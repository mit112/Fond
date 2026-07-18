# Fond Ember Folio — Claude Non-UI Handoff

> **Date:** 2026-07-18
>
> **Repository:** `/Users/mitsheth/dev/Fond`
>
> **Active worktree:** `/Users/mitsheth/.codex/worktrees/Fond/ember-folio-implementation`
>
> **Branch:** `codex/ember-folio-implementation`
>
> **Last completed implementation commit:** `80d9d37` (`feat: redesign Fond widgets as ambient keepsakes`)
>
> **Owner after this handoff:** Sol

## Purpose

Repair only the pre-existing non-UI native-macOS compilation/build-configuration blocker that prevents Task 8's required `platform=macOS` build. Preserve the locked product behavior and the existing uncommitted Ember Folio UI work. When the non-UI repair is verified and committed, stop and hand the branch back to Sol.

## Current implementation state

Tasks 1–7 of `2026-07-18-ember-folio-implementation.md` are complete in seven logical commits:

1. `6718037 feat: add Ember Folio design tokens`
2. `517cf59 feat: add keepsake card turn primitives`
3. `b234a28 feat: build the Ember Folio Now face`
4. `9eb2bda feat: model the Together moments thread`
5. `01ea215 feat: build the Together ritual and thread`
6. `52d5725 feat: integrate the Ember Folio connected experience`
7. `80d9d37 feat: redesign Fond widgets as ambient keepsakes`

The full iPhone 17 Pro test action passed after Task 6: 15 Swift Testing tests and 6 UI tests. During Task 8, the iPad Pro 13-inch (M5) iOS 27 build and Apple Watch Series 11 (46 mm) watchOS 27 build passed.

## Blocker evidence

- Task 8 requires `xcodebuild ... -destination 'platform=macOS' build`.
- `Fond/Fond.xcodeproj/project.pbxproj` declares `macosx` in `SUPPORTED_PLATFORMS` and a 26.0 macOS deployment floor.
- The scheme exposes native macOS, not Mac Catalyst.
- The unchanged baseline `Fond/Fond/Shared/Services/PushManager.swift` unconditionally imports UIKit and uses `UIApplication`, `UIDevice`, and `UIBackgroundFetchResult`.
- A signed native-macOS build first fails because the local provisioning profile lacks Communication Notifications. With `CODE_SIGNING_ALLOWED=NO`, compilation reaches the source failure and stops at `import UIKit`.
- `git diff 778b386 -- Fond/Fond/Shared/Services/PushManager.swift` is empty; this is not an Ember Folio regression.

## Dirty UI work owned by Sol

These files contain uncommitted Task 8 UI/platform presentation work. Do not edit, restore, stage, or commit them:

- `Fond/Fond/Views/ConnectedView.swift`
- `Fond/watchkitapp Watch App/Views/WatchConnectedView.swift`
- `Fond/widgets/FondDateWidget.swift`
- `Fond/widgets/FondDistanceWidget.swift`
- `Fond/widgets/widgets.swift`

Re-check `git status --short` before doing anything. If additional dirty files exist, treat them as user/Sol-owned unless this handoff explicitly authorizes them.

## Claude's authorized scope

- Diagnose the native-macOS compilation and repository-local signing/build configuration using read-only inspection first.
- Make the smallest non-UI repair needed for native macOS compilation.
- Platform-condition or adapt application lifecycle, notification registration, device identity, and background-fetch types only where required, while keeping iOS/iPadOS behavior byte-for-byte equivalent in effect.
- Add focused non-UI tests when they can prove platform selection or adapter behavior without Firebase/network writes.
- Modify service, app-lifecycle, entitlement, build-setting, and test files only when directly necessary.
- Use `Logger`, async/await, value types, and protocol-backed production/mock boundaries where a new boundary is required.
- Check current official Apple documentation before relying on uncertain macOS 27 notification, lifecycle, Firebase Messaging, or signing APIs.

## Hard prohibitions

- Do not change any SwiftUI view, widget rendering, watch presentation, design token, visual behavior, layout, typography, animation, accessibility presentation, or screenshot fixture.
- Do not start or implement Task 9.
- Do not change the feature set, crypto, Firestore schema, Cloud Functions, App Group keys, stored raw values, push payload contract, notification semantics, device document schema, or live Firebase state.
- Do not deploy, push, merge, or use the Apple Developer portal.
- Do not discard, stage, or commit Sol's dirty UI files.
- Do not weaken or remove the Communication Notifications capability merely to make local signing pass.
- Do not change any 26.0 deployment floor.
- Do not add AI attribution or `Co-Authored-By` trailers.

If a correct repair would alter locked notification behavior or requires UI work, stop without implementing it and report exact `file:line` evidence.

## Required workflow and verification

1. Read `AGENTS.md`, the approved design/spec documents, the implementation plan, and this handoff completely.
2. Confirm the branch, head, worktree, and dirty-file list.
3. Reproduce both the signed macOS failure and the unsigned compilation failure.
4. Inspect the full app lifecycle/push call graph before editing; do not patch only the first compiler error blindly.
5. Use TDD for any new logic boundary.
6. Run focused tests during implementation.
7. Run this native build after the repair:

   ```bash
   xcodebuild -project Fond/Fond.xcodeproj -scheme Fond -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
   ```

8. Attempt the plan's exact signed build separately:

   ```bash
   xcodebuild -project Fond/Fond.xcodeproj -scheme Fond -destination 'platform=macOS' build
   ```

   If repository code compiles but the installed provisioning profile remains the only failure, record that precisely; do not mutate external signing state.

9. Run the full iPhone regression action to prove the notification repair did not break the primary platform:

   ```bash
   xcodebuild -project Fond/Fond.xcodeproj -scheme Fond -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test
   ```

10. Re-run `git status --short` and verify Sol's five dirty files remain unstaged and otherwise untouched.
11. Update this document with the changed files, exact verification results, and any remaining local-signing limitation.
12. Commit only the non-UI repair and its tests/docs with one imperative commit message. Inspect the final message and exclude all AI attribution.
13. Stop. Do not continue into Task 8 UI work or Task 9. Report the resulting commit hash in the final handoff and return control to Sol with a concise remaining-work list.

## Claude non-UI repair — completed 2026-07-18

**Pre-flight verified:** branch `codex/ember-folio-implementation` @ `c7b11c6`; worktree `/Users/mitsheth/.codex/worktrees/Fond/ember-folio-implementation`; Xcode 27.0 (27A5218g). Starting dirty set = exactly the five Sol-owned UI files.

### Root cause

Native macOS has never compiled. `PushManager.swift` gated its full UIKit-dependent body on `#if canImport(FirebaseMessaging)` alone. Firebase Messaging *is* importable on native macOS, so the body compiled there and its unconditional `import UIKit` failed module resolution (`error: Unable to resolve module dependency: 'UIKit'`). A module-resolution error aborts compilation early — which is exactly why earlier inspection saw only `PushManager`: it masked every downstream type error. The macOS `AppDelegate` in `FondApp.swift` already never wires `PushManager` (it only calls `FirebaseApp.configure()`), so macOS needs `PushManager` to compile, not to function.

### Changed files (non-UI service layer only — 3 files, +14/-2)

- `Fond/Fond/Shared/Services/PushManager.swift` — guard changed to `#if canImport(FirebaseMessaging) && canImport(UIKit)`; the existing stub now also covers native macOS. iOS/iPadOS/visionOS/Catalyst unchanged (`canImport(UIKit)` is always true there).
- `Fond/Fond/Shared/Services/AuthManager.swift` — wrapped the Google Sign-In `UIViewController` presentation path in `#if canImport(UIKit)`; native-macOS `#else` surfaces a clear "unavailable on this platform" message (no silent failure; no invented `NSWindow` GID flow). iOS branch byte-for-byte identical.
- `Fond/Fond/Shared/Services/LocationManager.swift` — guarded the macOS-unavailable `.authorizedWhenInUse` case; macOS uses `.authorizedAlways`. iOS branch byte-for-byte identical.

No new logic boundary/adapter/value type was introduced, so no new unit test applies — these are compile-time platform selections; the compiler plus the unchanged iOS test suite are the verification. No SwiftUI view, widget, watch, token, entitlement, deployment floor, schema, crypto, payload, or notification-semantics change.

### Verification (exact commands + results)

- `xcodebuild … -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` → **BUILD FAILED, but the three service files compile with zero errors.** Every remaining native-macOS error is in the SwiftUI view layer (Sol's scope):
  - `Fond/Fond/Views/ConnectedView.swift:489,490` — `UIApplication` / `UIResponder` (`dismissKeyboard`) [protected dirty file]
  - `Fond/Fond/Views/ConnectedView+DataHandling.swift:62,306` — `WatchSyncManager` not in scope
  - `Fond/Fond/Views/PairingView.swift:134` — `UIPasteboard`; `:259` — `textInputAutocapitalization`
  - `Fond/Fond/Views/SettingsView.swift:154` — `navigationBarTitleDisplayMode`; `:156` — `topBarTrailing`
  - `Fond/Fond/Views/StatusPickerSheet.swift:46` — `navigationBarTitleDisplayMode`
- `xcodebuild … -destination 'platform=macOS' build` (signed) → **BUILD FAILED at provisioning validation only:** profile "Mac Team Provisioning Profile: com.mitsheth.Fond" lacks the Communication Notifications capability / `com.apple.developer.usernotifications.communication` entitlement. This gate runs before compilation, so this build never reaches the source phase. External signing state — untouched per scope. **The exact signed build does NOT pass.**
- `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test` → **TEST SUCCEEDED: 15 Swift Testing tests + 6 UI tests, 0 failures.** (Run with `-parallel-testing-enabled NO -test-timeouts-enabled YES`; an initial run wedged in an Xcode-27-beta parallel-`XCTestDevices` launch/debugger-attach hang unrelated to this source change.)
- `git diff --check` → clean.

### Protected files preserved

All five Sol-owned dirty UI files verified byte-identical to the session-start baseline (SHA-256) and unstaged: `ConnectedView.swift`, `WatchConnectedView.swift`, `FondDateWidget.swift`, `FondDistanceWidget.swift`, `widgets.swift`.

### Remaining blockers for Sol

1. The view-layer native-macOS errors listed above require UI edits (Sol's Task 8 macOS adaptation) — out of Claude's scope.
2. The local provisioning profile lacks Communication Notifications; the signed `platform=macOS` build cannot link until that profile is updated (Apple Developer portal / external signing — not Claude's to change).

### Architectural note (Mit's call)

The view layer is written for **Mac Catalyst** (`targetEnvironment(macCatalyst)` guards, `UIApplication`, `UIPasteboard`, `navigationBarTitleDisplayMode`, `horizontalSizeClass`), while the target is configured for **native macOS** (`SUPPORTED_PLATFORMS` includes `macosx`; scheme builds `platform=macOS`). Two coherent resolutions: (a) condition the view layer for native AppKit (larger UI effort), or (b) target Mac Catalyst instead (build-setting change; the existing UIKit view code compiles as-is; alters signing/distribution). Claude's service-layer guards are safe under both and do not foreclose either. Not decided here.

## Sol resume point

After Claude stops, Sol will review the non-UI diff, re-run proportionate verification, finish Task 8's regular-width/keyboard/UI requirements, commit Task 8, implement Task 9 sequentially, perform the full accessibility matrix, capture Now/Together light and dark plus a mid-turn frame, and stop for Mit's visual approval before any merge.

## Update — 2026-07-18: native macOS dropped (Mac widget via Continuity)

Mit's product decision: Fond is an iPhone + Apple Watch app; the Mac only needs the **widget**, which macOS 14+ provides automatically via **iPhone-widgets-on-Mac (Continuity)** — no Mac app required, and the Mac never touches keys/plaintext (it displays the iPhone-rendered widget). Accordingly:

- `Fond/Fond.xcodeproj/project.pbxproj`: removed `macosx` from `SUPPORTED_PLATFORMS` on the Fond app, widgets, NSE, and test targets. Inert `LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]` conditionals were left as harmless no-ops. **visionOS was also dropped** in a follow-up: `xros`/`xrsimulator` removed from the same targets (inert `XROS_DEPLOYMENT_TARGET = 26.0` left as a no-op). Fond now targets **iPhone + iPad + Apple Watch only**.
- **Supersedes the macOS items above:** the five view-layer native-macOS errors and the `platform=macOS` build requirement no longer apply. Task 8 reduces to iPad + keyboard + watch.
- The Mac provisioning limitation (Communication Notifications) is moot — there is no Mac app to sign.
- Commit `58b7807`'s service-layer guards are retained: harmless on iOS (`canImport(UIKit)` is always true there) and ready if a Catalyst Mac app is ever added.
