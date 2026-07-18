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

## Sol resume point

After Claude stops, Sol will review the non-UI diff, re-run proportionate verification, finish Task 8's regular-width/keyboard/UI requirements, commit Task 8, implement Task 9 sequentially, perform the full accessibility matrix, capture Now/Together light and dark plus a mid-turn frame, and stop for Mit's visual approval before any merge.
