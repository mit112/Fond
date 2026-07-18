# Fond — Roadmap to Live

> **Goal:** take Fond from "code-complete, verification 0%, un-producible build" (see `STATE_OF_PROJECT.md`) to **live on the App Store**, with **TestFlight beta** as the gate before public launch.
> **Planning date:** 2026-07-17 · **Method:** blueprint (dependency-ordered, one-PR-sized steps, per-phase verify gate).
>
> **UPDATE 2026-07-18:** The Xcode 27 build/runtime blocker is resolved. Before returning to release phases, implement the approved Two Faces / Ember Folio redesign using `docs/superpowers/plans/2026-07-18-ember-folio-implementation.md`. This is a view/widget/watch presentation pass only; release engineering resumes after its simulator, accessibility, and visual-approval gate.

## Legend — who executes

- 🤖 **LOOP** — an autonomous/agent loop can implement **and** verify this on ephemeral/test targets (compile, unit/emulator tests, lint). No secrets, no hardware, no live systems.
- 🧑 **ATTENDED** — requires you: physical devices, live Firebase/APNs, secrets, App Store Connect, or an irreversible cutover. The loop may *prepare* artifacts, but **you** run and approve the action.

> **Hard rule (per your standing directive):** the loop verifies on simulators/emulators/test targets only. Every live deploy, secret, real-device test, and the launch cutover is 🧑 attended — you hold the credentials and give the go.

## Dependency graph & parallelism

```
P0 (unblock build) ──┬─→ P1 (tests)      ─┐
   🧑→🤖             ├─→ P2 (hygiene/docs)─┼─→ P3 (device QA) ─→ P4 (App Store prep) ─→ P5 (TestFlight) ─→ P6 (launch)
                     │      🤖             │      🧑                🧑 (loop preps)        🧑                🧑
                     └──────────────────────┘
                     P1 ∥ P2 run in parallel (no shared files)
```

- **Critical path:** P0 → P3 → P4 → P5 → P6 (the attended spine).
- **Parallel de-risking:** P1 and P2 run concurrently with each other (and can overlap P3 prep) — they share no files.
- **Sequenced by risk:** unblock first (P0), then de-risk the crypto/backend with tests while it's cheap (P1), then the expensive attended validation (P3+).

---

## Phase 0 — Unblock the build & toolchain 🧑→🤖

**Goal:** produce a clean build of **all four targets** on this machine, and a clean `functions/` build+lint, so there is a known-green baseline for everything after.

**Why first:** every scheme is currently blocked by the missing watchOS 26 simulator runtime, and the main app target (Liquid Glass + MapKit reverse-geocode) has **never been compiled on the macOS-27-beta toolchain**. Nothing downstream is trustworthy until this is green.

**Tasks**
1. 🧑 Install the watchOS 26 simulator runtime — `xcodebuild -downloadPlatform watchOS` (or Xcode → Settings → Components). *This is the single blocker for all scheme builds.* Suggest running it yourself in-session: `! xcodebuild -downloadPlatform watchOS`.
2. 🤖 Build all four schemes for iOS/watchOS 26 sims (via XcodeBuildMCP `build_sim`, per your tooling preference): `Fond`, `watchkitapp Watch App`, `widgetsExtension`, `FondNotificationService`.
3. 🤖 Fix any macOS-27-beta toolchain compile breaks. **Watch closely:** `FondTheme.swift` (Liquid Glass `glassEffect`/`Glass`/`.interactive()`/`.tint()`) and `LocationManager.swift:165-168` (unguarded `MKReverseGeocodingRequest`) — the two highest-risk, currently-unverified APIs.
4. 🤖 `cd functions && npm ci && npm run build` (TypeScript 5.9). Resolve any `tsc` breaks.
5. 🧑→🤖 Decide the ESLint path: either **pin** ESLint 8 / typescript-eslint v5 and confirm `npm run lint` passes, **or** migrate to ESLint 9 flat config. (Lint runs in `predeploy` — it can block deploy in P3.)
6. 🧑 Confirm Google Cloud Functions supports the **`nodejs24`** runtime (`functions/package.json:13-14`). If not, pin `engines.node` to `nodejs22`. *Potential hard deploy blocker — verify before P3.*

**Exit criteria**
- All 4 schemes build with **0 errors** on iOS/watchOS 26 simulators.
- `functions/`: `npm run build` and `npm run lint` both green.
- `nodejs24` GCF support confirmed (or engine re-pinned).

**/verify gate:** `build_sim` green for `Fond` + `watchkitapp Watch App` + `widgetsExtension` + `FondNotificationService`; `functions` build+lint exit 0. Capture the warning count as a baseline.

---

## Phase 1 — Test the crypto & backend 🤖  *(runs parallel with P2)*

**Goal:** real automated coverage on the security-critical + server code, closing the #1 risk (currently ~0 tests, and this is an E2E-encrypted product).

**Why here:** cheapest, highest-leverage de-risking, fully loop-implementable+verifiable on simulators/emulators with **no hardware and no live backend**. Do it before spending attended device time in P3.

**Tasks** (TDD; strongest-model tier for crypto design)
1. 🤖 **Swift unit tests** (Swift Testing) for the crypto core: `EncryptionManager` AES-GCM round-trip + tamper-detection; `KeyExchangeManager` X25519+HKDF **both-partners-derive-identical-key** + determinism + the `"Fond-E2E-v1"` domain separation; `KeychainManager` store/load/delete; `UserStatus.displayInfo(forRawValue:)` unknown-value degradation; `DailyPromptManager` UTC-day rotation determinism; `FondMessage`/model encode-decode.
2. 🤖 **Cloud Functions tests** (`firebase-functions-test` + Firestore emulator): `linkUsers` transaction (happy path, expired code, self-pair, already-connected, double-claim race); `notifyPartner` payload shaping + stale-FCM-token cleanup; `unlinkConnection` idempotency; `expireCodes` cleanup. Add the missing `"test"` script to `functions/package.json`.
3. 🤖 **Firestore rules tests** (`@firebase/rules-unit-testing`): owner-only user writes, append-only + immutable `history`, connection-member reads, catch-all deny.

**Exit criteria**
- Crypto, Cloud Functions, and rules have real assertions (not boilerplate).
- `test_sim` (app) green; `cd functions && npm test` green; rules tests green against the emulator.
- Meaningful coverage on `Shared/Crypto/*` and `functions/src/*` (target the crypto + pairing paths specifically, not a blanket %).

**/verify gate:** `test_sim` + `functions` emulator tests + rules tests all green in CI-style run.

---

## Phase 2 — Code hygiene & doc truth 🤖  *(runs parallel with P1)*

**Goal:** eliminate the dead code and documentation drift the recon found, so future sessions aren't misled.

**Why here:** independent of tests (no shared files → parallel with P1), low risk, and it removes traps before attended phases.

**Tasks**
1. 🤖 Dead code: either **delete** `FondUser` (`Fond/Fond/Shared/Models/FondUser.swift`, never referenced) or **wire it** as the Firestore decode model (replacing raw-dictionary access) — pick one, don't leave it dangling; remove `FirebaseManager.lookupPairingCode(_:)` (zero call sites); fix the dead `isAuthorized` assignment (`HeartbeatManager.swift:71-77`).
2. 🤖 Doc truth pass: rewrite/retire the stale `docs/03-current-status.md`; correct `CLAUDE.md` (`ConnectionState` does **not** route the UI — it's App-Group only); remove/mark the **SwiftData** references in `docs/00-architecture-decisions.md` (never built); fix the `apnsHelper` "5th function" claim in `README.md`; reconcile the 4-vs-16 status count.
3. 🧑→🤖 Decide the **countdown cross-device sync** gap (anniversary syncs both ways, countdown doesn't): fix (add a self-doc listener) or explicitly de-scope for v1 and note it.

**Exit criteria**
- No unreferenced types/functions remain (verify with a dead-code pass).
- Docs no longer contradict the code; `STATE_OF_PROJECT.md` §3 drift items resolved.

**/verify gate:** build still green (P0 baseline unchanged); a grep/dead-code sweep finds no reintroduced markers.

---

## Phase 3 — Real-device integration validation 🧑

**Goal:** prove the push / widget / watch / health / location pipeline actually works — it has **never run on real hardware**, and NSE + widget push + HealthKit + background push cannot run in Simulator.

**Why here:** depends on a green build (P0) and is far more meaningful once crypto is test-covered (P1). This is the biggest unknown-unknown and is inherently attended.

**Tasks**
1. 🧑 Deploy backend to Firebase (`fond-cf7f5`): `firebase deploy --only functions,firestore:rules`. *Live system — your approval + credentials.* Confirm APNs secrets exist: `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` (`3P89U4WZAB`).
2. 🧑 **Resolve the APNs environment mismatch** before device tests: make `aps-environment` (entitlements) and `APNS_SANDBOX` (functions) consistent. For real-device dev, sandbox/sandbox; for TestFlight, production/production.
3. 🧑 On **two real devices** (iPhone + Apple Watch, two accounts): pair + key exchange; new-device key-sync (2nd device, iCloud Keychain); status / message / nudge / heartbeat / distance / daily-prompt round trips; widget refresh on home + lock + **StandBy**; **NSE decrypt with the app force-quit**; watch bidirectional; unlink cleanup on both sides.
4. 🧑 Confirm any Firestore composite index `expireCodes`/`codes` needs (Firebase logs a creation link on first failure).
5. 🤖 (support) Turn each reproducible defect found into a failing test, then fix (feeds back into P1's suite).

**Exit criteria**
- Every flow above verified on hardware; measured push→widget latency is acceptable (~<1.5s target).
- NSE path confirmed working when the app is force-quit; widget direct-APNs push confirmed.
- No P0/P1 defects open.

**/verify gate (attended):** a completed device test matrix (pass/fail per flow) + Cloud Function logs showing clean fan-out. 🧑 you sign off.

---

## Phase 4 — App Store submission readiness 🧑 *(loop preps artifacts)*

**Goal:** satisfy everything App Review requires. Several items are **hard gates** that block upload/approval.

**Tasks**
1. 🤖→🧑 **Privacy manifest** — add `PrivacyInfo.xcprivacy` for the app + each extension (none exist today): required-reason API declarations (UserDefaults/App Group, etc.) + collected data types (coarse location, heart rate/health, user content, identifiers). Loop can draft; you verify accuracy.
2. 🧑 **Encryption export compliance** — the app uses **non-exempt E2E crypto**; `ITSAppUsesNonExemptEncryption` is currently **absent** (undefined at upload). Decide the classification, set the key, and prepare the annual self-classification report / exemption as applicable.
3. 🧑 **Account deletion** (guideline 5.1.1(v)) — confirm the app offers full **account + data deletion** in-app, not just partner *unlink*. If it's unlink-only, this is a **build gap to implement** (delete Firebase Auth user + `users/{uid}` + connection + keys) — 🤖 loop can implement, 🧑 you verify on device.
4. 🧑 **App privacy "nutrition label"** in App Store Connect matching the manifest.
5. 🧑 **HealthKit review notes** (read-only heart rate, no writes — confirmed) + verify usage strings on every target that needs them.
6. 🧑 Verify **Sign in with Apple** presence (required because Google sign-in is offered — it *is* implemented; confirm it works on device in P3).
7. 🧑 App Store Connect metadata: full icon set, screenshots (iPhone 6.9"/6.5", iPad, Watch), description, keywords, **privacy-policy URL** (required), support URL, age rating; bump `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` from `1.0`/`1` as needed.

**Exit criteria**
- `xcodebuild archive` **validates** in Organizer with no privacy/entitlement/export errors.
- App Store Connect record complete; account deletion confirmed present.

**/verify gate (attended):** Xcode archive validation passes; App Store Connect readiness checklist complete. 🧑 you approve.

---

## Phase 5 — TestFlight beta 🧑

**Goal:** a real couple uses Fond on their own devices for a sustained period with no P0 bugs.

**Tasks**
1. 🧑 Archive (Release) → upload to App Store Connect → TestFlight internal, then external with a real couple.
2. 🧑 Monitor: Xcode Organizer crashes, Cloud Function logs (`firebase functions:log`), Firestore usage/quota. (Decide whether to add Crashlytics — not currently integrated.)
3. 🤖 Convert any reported bug into a regression test + fix (loops back to P1).

**Exit criteria**
- A real couple runs it ≥ ~1 week with no P0/P1 crashes or data-integrity issues.
- Push/widget latency and reliability acceptable in the wild.

**/verify gate (attended):** clean crash-free-sessions metric + a green beta-feedback pass. 🧑 you decide it's launch-ready.

---

## Phase 6 — Public launch 🧑 (irreversible cutover)

**Goal:** Fond is live on the App Store.

**Tasks**
1. 🧑 Submit for App Review; respond to any rejections (privacy/crypto/HealthKit/account-deletion are the likely question areas — all pre-addressed in P4).
2. 🧑 Release (phased or immediate).
3. 🧑 Production monitoring & alerting: Cloud Function error alerts, Firestore quota/billing, crash monitoring. Ensure `expireCodes` schedule and APNs certs are healthy.

**Exit criteria**
- App approved and live on the App Store.
- Monitoring/alerting in place; no P0 in the first release window.

**/verify gate (attended):** App Store status = "Ready for Sale"; post-launch dashboards green. 🧑 final sign-off.

---

## Session sequencing (suggested)

| Session | Phases | Mode |
|---|---|---|
| 1 | **P0** unblock build + toolchain | 🧑 install runtime → 🤖 fix compiles |
| 2–3 | **P1 ∥ P2** tests + hygiene/docs | 🤖 autonomous loop, verify on sims/emulator |
| 4 | **P3** device QA | 🧑 attended (hardware + live backend) |
| 5 | **P4** App Store prep | 🧑 (🤖 drafts manifest/metadata) |
| 6 | **P5** TestFlight | 🧑 attended |
| 7 | **P6** launch | 🧑 attended cutover |

**First action:** execute `docs/superpowers/plans/2026-07-18-ember-folio-implementation.md` in a fresh implementation session. After Mit approves final simulator captures, resume this roadmap at the first still-open verification/release phase.
