# Kickoff Prompt — Fond Verification Hardening (P0-backend · P1 · P2)

> Paste the block below into a fresh Claude Code session to execute the loop-implementable road-to-live work. It is scoped so it can be fully implemented **and** verified on simulators + the Firebase emulator — no hardware, no secrets, no live deploy.

---

Execute the Fond verification-hardening plan (Roadmap phases P0-backend, P1, P2). This is the loop-implementable work that follows the completed Ember Folio redesign.

Repository:  /Users/mitsheth/dev/Fond
Default branch: main (at 0698387, pushed to origin/main)
Xcode:       27.0 (27A5218g) at /Applications/Xcode-beta.app
Toolchain:   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

READ FIRST, COMPLETELY:
  docs/superpowers/plans/2026-07-18-fond-verification-hardening-plan.md   (the task-by-task plan)
  STATE_OF_PROJECT.md   and   ROADMAP.md                                   (why these tasks, exit gates)
  AGENTS.md   and   CLAUDE.md                                              (conventions, protected raw values)
  firestore.rules   and   functions/package.json                          (Task 5/6 anchors)

REQUIRED SUB-SKILL:
  Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans
  to work the plan task-by-task. Use superpowers:test-driven-development for every test task
  (write the failing test first, watch it fail, implement, watch it pass, commit).

WORKSPACE:
  Create a fresh isolated worktree/branch off main via superpowers:using-git-worktrees before touching code.
  Do NOT work directly in the main checkout. Keep one logical commit per task.

PLATFORM SCOPE (unchanged, non-negotiable):
  - Fond targets iPhone, iPad, and Apple Watch only. No native macOS/visionOS app.
  - Never restore macosx, xros, or xrsimulator to SUPPORTED_PLATFORMS.
  - Do not alter commit 58b7807's service-layer platform guards.

CURRENT STATE:
  - Ember Folio redesign is implemented, verified, Mit-approved, and integrated to main (0698387), pushed.
  - Loop-able gaps remain: functions toolchain (P0-backend), crypto/functions/rules tests (P1),
    dead-code + doc-truth (P2). The plan enumerates them as Tasks 1–9.

YOUR WORK:
  Implement Tasks 1–9 in dependency order per the plan. TDD throughout. After each task, run its
  verification and commit with the plan's message (imperative; no AI attribution / Co-Authored-By /
  generated-by lines — inspect each message before committing).

VERIFICATION (whole-plan gate):
  - FondTests action green on iPhone 17 Pro / iOS 27 (existing 23 + new crypto/model suites), 0 failures:
      DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Fond/Fond.xcodeproj \
        -scheme Fond -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
        -parallel-testing-enabled NO -test-timeouts-enabled YES test
  - cd functions && npm run build && npm run lint && npm test  → all exit 0 (emulator-backed)
  - Firestore rules tests green against the emulator
  - Dead-code sweep clean; docs no longer contradict code

AUTHORIZATION BOUNDARY:
  - Verify on simulators / the Firebase emulator / test targets ONLY.
  - Do NOT: firebase deploy, push, open a PR, touch the live fond-cf7f5 project, use APNs/secrets,
    run on physical devices, or do any App Store Connect work. Those are attended (Roadmap P3–P6).
  - Do NOT change crypto SOURCE, the Firestore schema, Cloud Function behavior, App Group keys,
    Keychain identifiers, stored raw values (UserStatus / FondMessage.EntryType), the push payload
    contract, notification semantics, or any 26.0 deployment floor.
  - Adding a functions "test" script + test devDeps is allowed (test infra, not behavior). Do not bump
    firebase-admin / firebase-functions majors.

STOP AND REPORT (do not guess) IF:
  - Synchronizable-Keychain writes are flaky on the simulator (Task 3) — do NOT weaken crypto to pass.
  - The ESLint 8-EOL migration (Task 1 Step 3) needs a call beyond the default "pin ESLint 8".
  - nodejs24 GCF support can't be confirmed and pinning to 22 needs Mit's sign-off (Task 1 Step 2).
  - The countdown cross-device sync decision (Task 9) needs Mit's Option A/B choice.
  - Any test reveals a real product defect (turn it into a failing regression test and surface it).

STOP CONDITION:
  Stop when Tasks 1–9 are complete and the whole-plan verify gate is green (or at the first blocker
  above). Report: per-task commit hashes, verification results, any decisions still needing Mit, and
  the final branch/worktree state. Do not merge, push, or deploy without explicit approval.
