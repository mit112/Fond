# Fond Verification-Hardening — Next-Session Review, Physical QA & Merge Handoff

> **Created:** 2026-07-18 (end of the verification-hardening execution session)
> **Branch:** `worktree-verification-hardening` (worktree `.claude/worktrees/verification-hardening`), off `main`@`97371cf`.
> **PR:** open (branch → `main`), **NOT merged** — merge is this handoff's endpoint, after review + attended physical QA + Mit's approval.
> **Status:** all 9 plan tasks implemented, per-task + whole-branch reviewed, whole-plan gate GREEN on simulators/emulator this session. Merge intentionally deferred so a real device QA pass can precede it.

This is the checklist to work in the **next** session. Sections A–D are the review/QA/merge steps; section E is the ready-to-paste kickoff prompt.

---

## A. Review checklist (before merge)

1. **Re-run both gates fresh** from the worktree and confirm green:
   - **Swift** (`iPhone 17 Pro / iOS 27`):
     ```bash
     DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
     xcodebuild -project Fond/Fond.xcodeproj -scheme Fond \
       -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
       -parallel-testing-enabled NO -test-timeouts-enabled YES test
     ```
     Expect `** TEST SUCCEEDED **` — **37 Swift Testing (12 suites) + 8 XCTest UI, 0 failures**.
   - **functions** (offline emulator):
     ```bash
     cd functions && npm ci && npm run build && npm run lint && npm test
     ```
     Expect all exit 0; `npm test` = **51 tests / 5 suites**.
2. **Constraint spot-check** (`git diff main..HEAD`): crypto source (`Fond/Fond/Shared/Crypto/*`) untouched; **no** `project.pbxproj` / `*.xcscheme` / `*.entitlements` / `*.xcconfig` / `Package.resolved`; no `SUPPORTED_PLATFORMS` / deployment-floor change; no `UserStatus` / `FondMessage.EntryType` raw-value renames; commits carry no AI attribution.
3. **Skim the behavior-sensitive diffs:** Task 9 `FirebaseManager.listenToOwnUserDoc` / `writeOwnCountdownToAppGroup` (must be a read-only new path + App-Group write, no Firestore write/schema change); Task 5 `notifyPartner.test.ts` (messaging mocked, `demo-fond`, no secrets); Task 6 `rules.test.ts` assertions vs `firestore.rules`.

## B. Physical device QA (2 devices, 2 accounts — the parts sim/emulator cannot cover)

The branch has exactly **one runtime behavior change (Task 9)** and **one auth-flow-adjacent deletion (Task 7)**. QA these specifically, then fold into the broader P3 matrix:

1. **Countdown cross-device sync — the Task 9 fix (highest priority):** On **device A**, set a countdown (date + label) in Settings. On **device B** (2nd device, same account, fresh sign-in — do NOT set it on B): confirm the countdown appears (correct date + **decrypted** label) in `ConnectedView` and the `FondDateWidget`. Then **clear** the countdown on A → confirm it clears on B. Confirm the label round-trips correctly and only ciphertext ever lands in Firestore.
2. **Watch heartbeat auth (Task 7 regression):** Task 7 removed a dead `isAuthorized` from the watch `HeartbeatManager`. Confirm the watch still requests HealthKit authorization and sends a heartbeat (auth flow intact; only dead write-only state was removed).
3. **Pairing (Task 7 regression):** Task 7 removed `FirebaseManager.lookupPairingCode` (server-side `linkUsers` is the real path). Confirm pairing + key exchange still works end-to-end.
4. **Full P3 matrix (this is also the start of attended P3):** pair / new-device key-sync / status / message / nudge / heartbeat / distance / daily-prompt / widgets (home + lock + StandBy) / **NSE decrypt with app force-quit** / watch bidirectional / unlink cleanup on both sides. The new tests give confidence in the crypto/backend *logic*, but the push/widget/watch/health pipeline has **never run on hardware**.

> Backend/rules changes on this branch are **test-only** (no function behavior change), so they need only the normal P3 backend-deploy verification, not separate device QA of function behavior.

## C. Watch-items to ratify (surfaced this session — decide during review)

- **`unlinkConnection` is non-idempotent but safe:** a 2nd unlink throws `failed-precondition` (first unlink atomically clears both users; nothing corrupts). The test asserts this real behavior. → Ratify as the v1 contract, or backlog a fix to make it a no-op.
- **`FondMessage` `Sendable` + MainActor-`Codable`:** latent Swift-6 warning; harmless today (production uses memberwise init only, never JSON codec of `FondMessage`). → Backlog design call (explicit `nonisolated` vs rework).
- **`expireCodes` composite index:** the `expiresAt < now AND claimed == false` query needs a **prod composite index**; the emulator auto-creates it, so green tests don't prove prod GC. → Create on first deploy (Firebase logs the creation link).
- **`nodejs24`:** confirmed GA this session → reconfirm at actual deploy time.

## D. Merge steps (only after Mit's explicit approval)

1. **AGENTS.md caveat (will block the merge otherwise):** `main`'s working tree has an **untracked** `AGENTS.md`; this branch adds a **tracked** one (Task 8 corrected + committed it per the plan). In the **main checkout**, `rm AGENTS.md` (or `git stash push -u` it) first, or the merge/checkout refuses with "untracked working tree file 'AGENTS.md' would be overwritten by merge."
2. If `main` advanced past `97371cf`, merge `main` into the branch (or rebase) and **re-run both gates** (§A1).
3. Merge the PR (squash or merge-commit per preference); delete the branch afterward.
4. **Post-merge:** proceed to attended **P3** (`firebase deploy --only functions,firestore:rules`) per `ROADMAP.md`.

## E. Ready-to-paste kickoff prompt for the next session

```
Resume the Fond verification-hardening branch for final review, attended physical QA, and merge.

Repository:  /Users/mitsheth/dev/Fond
Branch:      worktree-verification-hardening (worktree: .claude/worktrees/verification-hardening), HEAD 6d93e17, off main@97371cf. PR is open (branch → main), not merged.
Toolchain:   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer (Xcode 27.0, 27A5218g).

READ FIRST, COMPLETELY:
  docs/superpowers/plans/2026-07-18-verification-hardening-review-qa-kickoff.md  (this handoff — the full A–D checklist)

DO (in order):
  1. Re-run BOTH gates (§A1) and report results: Swift full FondTests on iPhone 17 Pro/iOS 27 (expect 37 Swift Testing + 8 XCTest UI, 0 failures); `cd functions && npm ci && npm run build && npm run lint && npm test` (expect 51 tests / 5 suites). If either regresses, STOP and report.
  2. Run the constraint spot-check (§A2) and skim the behavior-sensitive diffs (§A3). Report any drift.
  3. Support Mit's physical device QA (§B). Mit drives the two devices; you interpret results. Turn ANY reproducible defect into a failing regression test, then fix it (TDD) — the branch-specific priorities are countdown cross-device sync (Task 9), watch-heartbeat auth, and pairing.
  4. Get Mit's ratification on the §C watch-items.

THEN — ONLY after Mit's explicit approval:
  5. Merge (§D): handle the AGENTS.md untracked-in-main caveat FIRST, rebase if main moved (+re-run gates), merge the PR, delete the branch.

AUTHORIZATION BOUNDARY (unchanged):
  - Do NOT firebase deploy / touch the live fond-cf7f5 project / use APNs secrets / do App Store Connect work — attended P3+ begins AFTER merge.
  - Do NOT merge without Mit's explicit go.

STOP AND REPORT IF: a gate regresses; physical QA reveals a defect (→ regression test first); a merge conflict or main-advanced situation needs Mit's decision.
```
