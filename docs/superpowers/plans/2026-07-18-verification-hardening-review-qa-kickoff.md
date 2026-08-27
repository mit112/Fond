# Fond Verification-Hardening — Next-Session Review, Physical QA & Merge Handoff

> **Created:** 2026-07-18 (end of the verification-hardening execution session)
> **Branch:** `worktree-verification-hardening` (worktree `.claude/worktrees/verification-hardening`), off `main`@`97371cf`.
> **PR:** open (branch → `main`), **NOT merged** — merge is this handoff's endpoint, after review + attended physical QA + Mit's approval.
> **Status:** all 9 plan tasks implemented, per-task + whole-branch reviewed, whole-plan gate GREEN on simulators/emulator this session. Merge intentionally deferred so a real device QA pass can precede it.

This is the checklist to work in the **next** session. Sections A–D are the review/QA/merge steps; section E is the ready-to-paste kickoff prompt.

---

## Session 2026-07-20 — §A re-verified green (review pass 2)

Re-ran both gates fresh from the worktree at HEAD `4e5439b` (main still `97371cf`; PR #1 `MERGEABLE`/`CLEAN`):
- **Swift** (iPhone 17 Pro / iOS 27): `37 tests / 12 suites` + `8 XCTest UI`, 0 failures → `** TEST SUCCEEDED **`. ✅
- **functions**: `51 tests / 5 suites`, exit 0. ✅
- **§A2** constraints CLEAN; **§A3** diffs CLEAN (no drift) — `notifyPartner.ts`'s only change is a lint quote-swap; `firestore.rules` is UNCHANGED (Task 6 is test-only); `firestore.indexes.json` is empty (confirms §C-3).

**⚠️ Simulator gotcha (hit this session):** the first Swift run failed **exit 65** — *not* a code regression — because the `iPhone 17 Pro` sim (UDID `65FAAD62-8B8C-49EF-997D-817731BFCD91`) had corrupted data (`device's data no longer present on disk`). The build SUCCEEDED and zero tests ran. Fix before re-running:
```bash
xcrun simctl shutdown 65FAAD62-8B8C-49EF-997D-817731BFCD91 || true
xcrun simctl erase 65FAAD62-8B8C-49EF-997D-817731BFCD91
xcrun simctl bootstatus 65FAAD62-8B8C-49EF-997D-817731BFCD91 -b
```
Then target the gate by `-destination 'platform=iOS Simulator,id=65FAAD62-…'` (by UDID, not name — a stale runtime-less duplicate "iPhone 17 Pro" makes name matching ambiguous).

**Still pending (next session):** §B physical device QA (Mit-driven), §C ratification, §D merge. **§E below is refreshed for that session.**

---

## ✅ Session 2026-08-26 — §A re-run, §D MERGED. This handoff's endpoint is reached.

**§D done.** `worktree-verification-hardening` (HEAD `3ef3657`) merged into `main` as **`1fced63`** — a true merge, not `--ff-only`, because `main` carried `b6124a4`. Clean auto-merge, **zero conflicts**. The three previously-unpushed branch commits (`5fd3d61`, `6cf11af`, `3ef3657`) were pushed first so PR #1's record is complete; **PR #1 auto-closed as MERGED**. `main` pushed to `origin`.

**§A re-run green on the merged tree** (not on the branch): Swift `test_sim` on iPhone 17 Pro — **45 passed / 0 failed** (39 Swift Testing in 13 suites + 9 XCTest UI); `functions` `npm ci && build && lint && test` — **51 tests / 5 suites, exit 0**. Four-target build **0 errors, 0 compiler warnings, 93s**, all four products emitted with fresh mtimes, NSE still embeds zero frameworks.

**Two merge frictions worth recording:**
- The **`AGENTS.md` caveat below was out of date.** By 2026-08-26 `main`'s untracked `AGENTS.md` was a **symlink → `CLAUDE.md`** (created 2026-08-24), not a copy. It was moved aside for the merge; afterwards, per Mit, the branch's near-duplicate tracked file was replaced by a **tracked symlink** (`4f8fa35`) — the file still exists for a fresh clone, with one source of truth.
- **Stale `.git/index.lock` twice.** One dated 2026-08-03 blocking the merge, and a second appearing mid-session at 21:26 (Xcode's own `git` re-indexing after file changes). Both had no holder — `lsof .git/index.lock` empty, no `git` process. Check before assuming a git failure is yours.

**Also landed, outside this plan:** `FondTests/DecryptPerformanceTests.swift` (`5cd8d0f`) measures the NSE payload decrypt at **5.5µs median / 6.3µs p99** on an iPhone 15 (A16, iOS 27) and asserts a 1ms p99 budget. The contradictory `<1ms` / `<10ms` comments in `NotificationService.swift` are reconciled (`555d75b`).

**Still pending:** **§C ratification** (below) and the **full P3 device matrix** — §B item 1 (countdown cross-device sync, the Task 9 fix) and items 2–4 were never completed; only the toolbar hit-test finding was. §C is now the blocker for P3.

---

## Session 2026-07-23 — QA-support: device bug found + fixed (branch HEAD now `6cf11af`)

Started §B on Mit's iPhone. First real-device finding was a **UI hit-testing bug**, now fixed:

- **Bug:** ConnectedView toolbar top-left (gear/Settings) + top-right (list) icon buttons — and the send button — were **dead to a finger**. Cause: an SF Symbol glyph in a 44/52pt frame with **no `.contentShape`** → only the glyph is hit-testable; a finger misses it. **Device-only:** every synthesized tap (XCUITest `.tap()` AND faithful AXe HID `tap`) lands dead-center on the glyph, so it never reproduces in the Simulator. The first hypothesis (iOS 26 interactive-glass-on-container stealing taps) was WRONG — the middle text picker worked inside the same glass; the `interactive:false` change was kept only as an Apple-aligned safeguard.
- **Fix — committed `6cf11af`** (6 files; scheme excluded; no AI attribution): `.contentShape(Rectangle())` on the icon buttons + send button; **removed the redundant one-way trailing "Together" icon** and recomposed the toolbar as leading-Settings + optically-centered picker (nav-bar pattern) in app + gallery; container glass kept passive. Verified: compiles clean, **3 UI tests pass**, sim screenshot good. **Toolbar fix device-confirmed by Mit**; the new layout + send button still want a quick device eyeball.
- **Tooling:** enabled XcodeBuildMCP's `ui-automation` workflow (AXe HID taps) — `claude mcp` env `XCODEBUILDMCP_ENABLED_WORKFLOWS=project-discovery,simulator,simulator-management,session-management,ui-automation,debugging`. Durable for future sessions.
- **`main` advanced `97371cf` → `b6124a4`** ("Add MIT license" — benign, non-conflicting; adds `LICENSE` + 1 README line). PR #1 still **MERGEABLE/CLEAN**, but a local `--ff-only` into main is **no longer possible** (divergence) → merge via GitHub, or merge `main`→branch first then gate.
- **Branch state:** HEAD `6cf11af`; local commits (`5fd3d61` docs + `6cf11af` fix) are **ahead of `origin`/unpushed**. Xcode keeps rewriting `watchkitapp Watch App.xcscheme` in the worktree working tree — not committed; `git checkout` it before any merge (§A2 forbids scheme changes).

**Still pending:** full P3 device matrix, §C ratification, §D merge. Kickoff prompt below is refreshed for that session.

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
Resume the Fond verification-hardening branch: attended physical QA, §C ratification, then merge.

Repository:  /Users/mitsheth/dev/Fond
Branch:      worktree-verification-hardening (worktree: .claude/worktrees/verification-hardening), off main@97371cf.
             PR #1 open (branch → main), MERGEABLE/CLEAN, NOT merged. HEAD = current branch tip
             (run: git -C .claude/worktrees/verification-hardening rev-parse HEAD).
Toolchain:   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer (Xcode 27.0, 27A5218g);
             system xcode-select already points here.

READ FIRST, COMPLETELY:
  docs/superpowers/plans/2026-07-18-verification-hardening-review-qa-kickoff.md
  (A–D checklist + the "Session 2026-07-20" re-verification note near the top)

STATUS CARRIED IN (verified 2026-07-20 — do NOT re-derive):
  - §A DONE & GREEN: Swift 37 tests/12 suites + 8 XCTest UI (0 failures); functions 51 tests/5 suites.
    §A2 constraints CLEAN; §A3 diffs CLEAN (Task 9 = read-only self-doc listener + App-Group write;
    Task 5 mocked/no-secrets; Task 6 mirrors UNCHANGED firestore.rules; Task 7 removed only dead
    isAuthorized; notifyPartner.ts = lint quote-swap only).
  - Sim gotcha: Swift gate exit 65 + "Unable to boot device / data no longer present" = corrupted sim
    (NOT a regression) — erase + reboot (see handoff doc) and re-run by -destination id=<UDID>.

DO (in order):
  1. Sanity only: confirm main is still 97371cf and PR #1 still MERGEABLE. Re-run BOTH gates ONLY if
     main moved (or you want fresh insurance) — §A is already green at the current HEAD. If a gate
     regresses, STOP and report.
  2. Support my physical device QA (§B) — I drive two devices; you interpret results and turn ANY
     reproducible defect into a FAILING regression test first, then fix it (TDD). Priorities:
       (a) countdown cross-device sync (Task 9): set date+label on device A → confirm decrypted
           appearance in ConnectedView + FondDateWidget on device B (same account, fresh sign-in,
           don't set on B) → clear on A → clears on B; only ciphertext in Firestore.
       (b) watch heartbeat auth (Task 7 regression).
       (c) pairing + key exchange end-to-end (Task 7 regression).
     Then the full P3 matrix (status/message/nudge/heartbeat/distance/daily-prompt/widgets
     home+lock+StandBy / NSE decrypt with app force-quit / watch bidirectional / unlink cleanup both sides).
  3. Get my ratification on the §C watch-items:
       (1) unlinkConnection non-idempotent-but-safe (2nd call → failed-precondition) → ratify as v1 vs
           backlog a client no-op;
       (2) FondMessage Sendable + MainActor-Codable latent Swift-6 warning → backlog;
       (3) expireCodes prod composite index (firestore.indexes.json is EMPTY) → create at first deploy;
       (4) nodejs24 → reconfirm GA at deploy.

THEN — ONLY after my explicit approval:
  4. Merge (§D): handle the AGENTS.md untracked-in-main caveat FIRST — in the MAIN checkout,
     `rm AGENTS.md` (or `git stash push -u`), since main has it UNTRACKED and the branch TRACKS it,
     else the merge/checkout refuses. Re-run both gates if main moved. Merge PR #1, delete the branch.

AUTHORIZATION BOUNDARY: no firebase deploy / live fond-cf7f5 / APNs secrets / App Store work until
AFTER merge (attended P3 deploy = firebase deploy --only functions,firestore:rules begins post-merge).
Do NOT merge without my explicit go.

STOP AND REPORT IF: a gate regresses; physical QA reveals a defect (→ regression test first);
a merge conflict or main-advanced situation needs my decision.
```
