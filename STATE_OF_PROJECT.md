# Fond — State of the Project

> **Assessment date:** 2026-07-17
> **Assessment type:** Read-only revival audit (no code changed this session)
> **Last commit:** `a8db595` — 2026-03-21 · **Pause length:** 118 days (~3.9 months)
> **Method:** 5 parallel read-only recon agents + real compiler builds + manifest/entitlement inspection. Each claim is tagged **[VERIFIED]** (I ran/read it) or **[INFERRED]** (reasoned, not confirmed).
>
> **⏱ UPDATE 2026-07-17 (later same day):** The build/toolchain blockers below are **RESOLVED**. Migrated **Xcode 26 → 27 beta** — removed Xcode 26 + the iOS 26 runtime, installed iOS 27 + watchOS 27. The **full `Fond` scheme now builds clean on Xcode 27: 0 errors, 0 warnings** (app + embedded watch app + widgets + NSE). This confirms the items flagged unverified below — the **main app target, Liquid Glass (`FondTheme`), and `MKReverseGeocodingRequest` (`LocationManager`)** all compile on the iOS/watchOS 27 SDKs. Any statement below of "build un-producible" or "main-app compile unverified" is superseded by this note.
>
> **🎨 UPDATE 2026-07-18:** The replacement connected experience is fully designed but **not implemented**. Locked product structure: `docs/superpowers/specs/2026-07-17-fond-redesign-design.md`. Approved Ember Folio visual system: `docs/superpowers/specs/2026-07-18-fond-ember-folio-visual-system-design.md`. Execution-ready plan: `docs/superpowers/plans/2026-07-18-ember-folio-implementation.md`. The next code session should execute that plan without reopening IA, product scope, crypto, backend, or storage contracts.
>
> **✅ UPDATE 2026-07-18 (evening) — redesign shipped to `main`:** The Ember Folio redesign is now **implemented, verified, Mit-approved, and integrated to `main` at `0698387` (pushed to `origin/main`)**. The full `Fond` test action passes on iPhone 17 Pro / iOS 27 (**23 tests, 0 failures**); iPad, watch, and widget builds succeed on Xcode 27. This **resolves the app-side P0 concerns in §6** — the build is producible and the two "highest compile-breakage candidates" (Liquid Glass `glassEffect`, `MKReverseGeocodingRequest`) now compile *and* test green. Platform scope narrowed to **iPhone + iPad + Watch** (native macOS + visionOS dropped; Mac widget via Continuity). **Still open (loop-able):** the `functions/` toolchain (P0-backend), crypto/Cloud-Functions/rules tests (P1 — the redesign added only UI/model tests), and dead-code + doc-truth (P2) — packaged task-by-task in `docs/superpowers/plans/2026-07-18-fond-verification-hardening-plan.md`. Attended P3–P6 (device QA, `firebase deploy`, App Store) unchanged.

---

## 0. TL;DR verdict

Fond is a **coherent, feature-complete, production-styled iOS 26 couples app** — not an abandoned scaffold. The code the recon touched is clean: zero TODO/FIXME debt, no debug-gated half-features, no fake-data stubs, real Firestore security rules, a real 365-entry content file. It was declared "ship-ready" in March 2026 and then the developer immediately pivoted into a UI redesign, paused mid-session, and never returned.

**It is in good shape as a codebase, but not close to "live."** The gap to launch is **not** more features — it's **verification and release plumbing**, none of which was ever done:

1. **Automated tests are essentially zero** — the E2E-crypto and Cloud Function core is completely unverified. [VERIFIED]
2. **Nothing has ever run on real hardware** — NSE, widget push, HealthKit, and location cannot be validated in Simulator, and no TestFlight build was ever cut. [VERIFIED — no tags/releases in git]
3. **App Store submission artifacts are missing** — no privacy manifest, no encryption export-compliance declaration, an APNs environment mismatch. [VERIFIED]
4. **The build cannot currently be produced on this machine** — the watchOS 26 simulator runtime is not installed, which blocks every scheme. [VERIFIED]

The yardstick and the honest score are in §6. The forward plan is in `ROADMAP.md`.

---

## 1. Purpose (reconstructed from code + docs)

**Fond is a privacy-first "couples widget" app** for iOS 26 / iPadOS 26 / macOS Tahoe / watchOS 26. Two partners pair via a 6-character code, exchange encryption keys, and then share ambient presence — a status, a short message, nudges, an Apple Watch heartbeat, location distance, and a shared daily prompt — surfaced primarily on **home/lock-screen widgets and the Watch Smart Stack** rather than inside the app. All user content is **end-to-end encrypted client-side (X25519 ECDH → HKDF → AES-256-GCM)**; the Firebase backend only ever stores ciphertext.

- **Tagline / promise:** "Your Person, At a Glance" (`README.md:1`); the stated emotional core is **"presence without pressure"** / ambient intimacy / calm technology (`docs/superpowers/specs/2026-03-21-connected-view-redesign.md:12,18`). **"The widget IS the product"** (`docs/02-design-direction.md:16`). [VERIFIED]
- **Audience:** romantic couples, with an explicit long-distance-relationship lean (distance widget, countdown, heartbeat) (`docs/03-feature-expansion-plan.md:182,431,556`). [VERIFIED]

### Feature inventory (all present in code) [VERIFIED]
Auth (Apple + Google) · display-name setup · 6-char-code pairing (server-side atomic `linkUsers`) · E2E encryption pipeline · new-device key-sync wait screen · 16 statuses in 4 categories · 100-char encrypted messaging (5s cooldown) · long-press nudge (30s cooldown) · Apple Watch heartbeat via HealthKit · privacy-rounded location distance (on-device haversine + reverse geocode) · 365 bundled daily prompts (deterministic UTC rotation, both-answer reveal) · days-together counter + countdown · 3 widgets (up to 5 families) · watchOS Smart Stack relevance · Notification Service Extension (payload fast-path decrypt) · dual-path push + direct-APNs widget push · append-only encrypted history · settings + clean unlink.

---

## 2. Architecture map [VERIFIED]

One Xcode project → **4 targets** + an independent TypeScript backend. Shared code lives in `Fond/Fond/Shared/` and is compiled into multiple targets via target membership (not a framework/module).

| Component | Role | Key files |
|---|---|---|
| **Fond** (iOS/iPadOS/macOS) | The app | `FondApp.swift` (Firebase init, AppDelegate), `ContentView.swift` (router), `Views/*`, `Shared/Services/*` |
| **watchkitapp Watch App** | Read-only companion; never touches Firebase — proxies through the phone | `WatchDataStore.swift`, `HeartbeatManager.swift`, `Views/WatchConnectedView.swift` |
| **widgetsExtension** | Pure display; reads decrypted data from App Group UserDefaults | `widgets.swift`, `FondDateWidget.swift`, `FondDistanceWidget.swift`, `FondWidgetPushHandler.swift` |
| **FondNotificationService** (NSE) | Intercepts pushes, decrypts payload with CryptoKit, writes App Group, reloads widgets. **No Firebase SDK.** | `NotificationService.swift` |
| **functions/** (Firebase v2, TS) | Privileged ops | `linkUsers.ts`, `notifyPartner.ts`, `unlinkConnection.ts`, `expireCodes.ts`, helper `apnsHelper.ts` |

### Critical data flows
- **Pairing + key exchange:** `publishPublicKey` (writes plaintext `publicKey`) → `linkUsers` Cloud Function (atomic transaction: claim code + create `connections/{id}` + set `partnerUid`/`connectionId` on both users; server-side because Firestore rules forbid writing a partner's doc) → `completeKeyExchange` → X25519 DH + HKDF-SHA256 (salt `"Fond-v1"`, info `"Fond-E2E-v1"`) → symmetric key in iCloud-synced Keychain (`FirebaseManager.swift:79-137`, `KeyExchangeManager.swift:20-63`).
- **Send status/message:** `EncryptionManager.encrypt` (AES-GCM, nonce+ciphertext+tag, Base64) → `updateData` on `users/{uid}` + append-only `history` doc → fire-and-forget `notifyPartner` (`FirebaseManager.swift:142-193,305-320,410-420`).
- **Push (dual/triple path):** `notifyPartner` forwards ciphertext in the FCM data payload, sends all types as `alert` + `mutable-content:1`, then fires a **direct-APNs widget push 500ms later** to avoid a stale-App-Group race. Receivers: **NSE fast path** (decrypts payload, works when force-quit), **main-app fallback** (`PushManager`), **foreground listener** (`ConnectedView`) (`notifyPartner.ts`, `NotificationService.swift`, `PushManager.swift`).
- **Widgets:** App Group `group.com.mitsheth.Fond` UserDefaults is the shared bus; app/NSE write decrypted plaintext, widgets read it, `WidgetCenter.reloadAllTimelines()` refreshes.
- **Watch:** `WatchConnectivity.updateApplicationContext` (phone→watch state) + `sendMessage`/`transferUserInfo` (watch→phone nudge/heartbeat, re-entering the standard encrypt→write→push pipeline).

### External dependencies [VERIFIED]
- **Firebase used:** Auth (Apple+Google), Firestore (`users`/`connections`/`codes` + `devices`/`history` subcollections; real rules with append-only history + catch-all deny), FCM, Cloud Functions v2 (`us-central1`). App Check SDK is pinned but **unused**; no Realtime DB / Storage.
- **SPM:** firebase-ios-sdk **12.9.0**, GoogleSignIn **9.1.0** (+ transitive graph, internally consistent).
- **npm (functions):** firebase-admin **13.6.1**, firebase-functions **7.0.5**, TypeScript **5.9.3**, Node engine **24**.

---

## 3. What works / broken / stubbed / untested

### Build reality [VERIFIED — I ran the compiler this session]
- ❌ **No scheme builds on this machine.** `Fond`, `FondNotificationService`, and `widgetsExtension` schemes all fail **fast (pre-compile)** with: *"This scheme builds an embedded Apple Watch app. watchOS 26.0 must be installed in order to run the scheme."* The **watchOS 26 simulator runtime is not installed** (only iOS 26.0 sims exist). A generic-destination build fails the same way. This is an **environment gap, not a code defect** — exactly the macOS-27-beta caveat.
- ✅ **The Shared layer + extensions compile clean.** Building the `FondNotificationService` and `widgetsExtension` targets **directly** (`xcodebuild -target …`, bypassing the watch-embedding scheme) both succeed: **exit 0, 0 errors, 1 warning each.** This compiles the crypto path (`EncryptionManager`, `KeychainManager`), models, `FondConstants`, `FondColors`, and all WidgetKit code (`AppIntentConfiguration`, `containerBackground`, `.pushHandler`) against the current toolchain.
- ⚠️ **The main app target is UNVERIFIED.** [INFERRED risk] Because every app/watch scheme is runtime-blocked and `FondTheme` (Liquid Glass) + `LocationManager` are app-target-only, the two APIs most likely to break on a newer SDK — **`glassEffect`/`Glass` (`FondTheme.swift:117,150,167,181`) and `MKReverseGeocodingRequest` (`LocationManager.swift:165-168`)** — were **not compiled**. Their status on the macOS-27-beta toolchain is unknown until the watchOS runtime is installed and the app scheme builds.

### Source-level completeness [VERIFIED]
- ✅ **No debt markers** — zero TODO/FIXME/HACK/XXX across Swift + TS (only WidgetKit `placeholder(in:)` API and one intentional `#else`-stub comment).
- ✅ **No fake-data stubs** in production paths; `fatalError` in `AuthManager` is correct defensive handling; the `#else` `PushManager` no-op and the empty `WCSessionDelegate` method are intentional.
- ✅ **No `#if DEBUG` gating** of incomplete features; APNs sandbox is a config param defaulting to production.
- ⚠️ **Dead code (2 artifacts):** `FondUser` struct is **never referenced** (`FirebaseManager` reads Firestore via raw dictionary access — the 13-field model is schema-documentation only); `FirebaseManager.lookupPairingCode(_:)` has **zero call sites** (superseded by server-side `linkUsers`). Also a dead `isAuthorized` assignment in `HeartbeatManager.swift:71-77`.

### ❌ Tests — the dominant gap [VERIFIED]
Effectively **zero real tests.** Six test functions exist across the iOS + watch test targets; **none contains a single assertion** (empty `@Test func example()` + Xcode boilerplate). `functions/` has **no test files and no `test` script** (`firebase-functions-test` is a devDependency but unused). **Completely untested:** AES-GCM crypto, X25519/HKDF key exchange, Keychain, the entire Firestore layer, all Cloud Functions (pairing transaction, push fan-out, APNs JWT signing), the NSE decrypt path, and every view. **For an E2E-encrypted product, this is the single largest risk.**

### Latent correctness risks the recon surfaced [VERIFIED — findings; INFERRED — impact]
- **APNs environment mismatch:** app + widget entitlements set `aps-environment = development` (`Fond.entitlements:17`, `widgetsExtension.entitlements:13`) while the Cloud Functions default `APNS_SANDBOX = false` (production host). Dev builds would get sandbox tokens but the direct-APNs widget push targets the production host → widget pushes fail in dev; must be made consistent before TestFlight (which needs production/production).
- **Countdown never syncs across devices — RESOLVED (Option A, self-doc listener):** `anniversaryDate` syncs via the connection doc; the user-doc `countdownDate`/`countdownLabel` fields are now read back on every device by `FirebaseManager.listenToOwnUserDoc` → `writeOwnCountdownToAppGroup` (decrypts the label, writes both to the App Group). Schema/encrypted-field names unchanged; new read path only.
- **Crypto migration footnote:** `KeyExchangeManager.swift:51-52` documents that HKDF `sharedInfo` was changed to `"Fond-E2E-v1"` pre-launch — harmless for a clean launch, load-bearing if any pre-change keys ever went live (they didn't).

---

## 4. Staleness (what rotted during the pause) [VERIFIED pins; INFERRED currency]

> No package registry was queried this session. Pinned versions are read from manifests; "newer likely exists" is training-knowledge inference, not a confirmed lookup.

**Deployment targets:** all four platforms baseline **26.0**; `SWIFT_VERSION = 5.0` (`project.pbxproj`). Compiling on the macOS-27-beta toolchain uses the **27-beta SDKs** — `#available` guards protect runtime but **not** compile-time signature/rename changes.

| Area | Pinned | Risk |
|---|---|---|
| firebase-ios-sdk | 12.9.0 | Current-as-pinned; may need a manual bump for 27-beta SDK compat. |
| GoogleSignIn-iOS | 9.1.0 | Current-era; fine. |
| firebase-admin / firebase-functions | 13.6.1 / 7.0.5 | **Low risk** — code already uses the v2 modular API + params, no `functions.config()`. |
| TypeScript | 5.9.3 | Fine, but see eslint mismatch. |
| **ESLint + @typescript-eslint** | **8.57.1 / v5** | ⚠️ **ESLint 8 is EOL (Oct 2024); @typescript-eslint v5 predates TS 5.9** → parser warnings/errors. Runs in `predeploy` lint → can **block deploy**. Bumping to ESLint 9 requires a flat-config migration (the `.eslintrc` + `--ext` flag are removed in v9). |
| **Node engine `24`** | package.json:13-14 | ⚠️ [INFERRED] **Verify Google Cloud Functions supports `nodejs24` at deploy time.** Through the knowledge cutoff GCF Gen2 topped out at `nodejs22`. If unsupported, this is a **hard deploy blocker** → pin to `nodejs22`. |

**Highest compile-breakage candidates on the newer toolchain** (unverified — app target didn't build): Liquid Glass `glassEffect`/`Glass`/`.interactive()`/`.tint()` (`FondTheme.swift`, the *only* `#available` guards in the codebase); **unguarded** `MKReverseGeocodingRequest` stack (`LocationManager.swift:165-168`); WidgetKit `WidgetPushHandler`/`WidgetPushInfo`/`.pushHandler` (compiled clean this session — **lower risk than feared**); AppIntents `RelevantIntentManager`.

---

## 5. History & why it stalled [VERIFIED git; INFERRED motive]

20 commits, single `main` branch, **no other branches, no stashes, no tags/releases**. Working tree clean except untracked `.claude/` and `.superpowers/` tooling dirs.

| Date | Milestone |
|---|---|
| 2026-02-24 | Initial scaffold (~23.5k lines in one shot); "first pairing test passed" |
| 2026-03-05 | "Complete app" milestone + NSE + Liquid Glass + recruiter-ready README |
| 2026-03-18→19 | Architectural-review hardening cycle (16 P0–P3 issues) → CLAUDE.md declares ship-ready |
| 2026-03-21 | "Breathing Hub" ConnectedView redesign (spec + 8-task plan + 8 commits in one ~2h session) — **the final direction** |

**[INFERRED] Why it stalled:** The developer declared the app ship-ready on Mar 19, then **immediately opened a large UI redesign** on Mar 21 and **paused mid-session without a verification/sign-off commit** (the redesign plan's final "visual verification" step never landed; the session ends on a catch-all "commit pending changes" + a one-line param removal). There is **no SCM blocker** — no parked branch, no lost stash. It reads as a **motivational/attention pause on an unverified redesign**, not a technical wall. It was never tested on device and never shipped.

---

## 6. Honest assessment

**Yardstick (reconstructed, stated explicitly):** "Live" is not defined in any doc, so I interpret it as **public availability on the App Store**, with **TestFlight beta** as the milestone immediately before. I measure progress against *that*, not against "does the code look done." (If you meant something narrower — e.g. just a working TestFlight build for two people — tell me and the roadmap compresses.)

**Are we in good shape?** **Yes on engineering, no on shippability.** The build quality is genuinely high for a solo greenfield project — the architecture is sound, the zero-knowledge design is real, and the code that compiled did so cleanly on a *newer* toolchain than it was written for. But measured against "on the App Store," the project is roughly at **"code-complete, verification 0%."** Every remaining task is release engineering, and the two hardest (real-device validation, App Store review artifacts) are **attended, human-in-the-loop** work that no agent loop can finish alone.

### Top risks & unknowns (ranked)
1. **[VERIFIED] Zero automated tests on E2E crypto + Cloud Functions.** A silent crypto/key-derivation regression would corrupt the product's one non-negotiable promise, with no test to catch it. *Highest priority to fix; loop-implementable.*
2. **[VERIFIED] The entire push/widget/watch/health/location pipeline has never run on real hardware, ever.** NSE, widget push, HealthKit, and background push simply don't work in Simulator. This is the biggest *unknown-unknown*. *Attended (hardware + live backend).*
3. **[VERIFIED] App Store submission gates are unmet:** no `PrivacyInfo.xcprivacy`, no `ITSAppUsesNonExemptEncryption` (the app uses non-exempt E2E crypto — undefined behavior at upload), APNs env mismatch, and **account deletion may be missing** (App Store guideline 5.1.1(v) — only *unlink* is confirmed, not full account+data deletion). *Attended.*
4. **[VERIFIED] Build is currently un-producible** (missing watchOS 26 runtime) → the **main app target's compilation on the beta toolchain is unverified**, including the two riskiest APIs (Liquid Glass, MapKit reverse-geocode). *Fast attended unblock, then loop-verifiable.*
5. **[INFERRED] Possible deploy blockers:** `nodejs24` GCF support unconfirmed; ESLint-8-EOL/TS-5.9 lint runs in `predeploy`. *Quick to verify; loop-implementable once confirmed.*
6. **[VERIFIED] Documentation drift** (`docs/03-current-status.md` is stale/miscounts; CLAUDE.md claims `ConnectionState` routes the UI but it doesn't; SwiftData documented but never built; README calls `apnsHelper` a 5th function). Low technical risk, but it will mislead future sessions. *Loop-implementable.*

### What the original design got right, and the one thing to reconsider
- **Keep:** the zero-knowledge crypto model, the App-Group data bus, server-side `linkUsers`/`unlinkConnection`, the fire-and-forget push + listener-fallback reliability model, and "widget-first" product framing. All sound.
- **Reconsider (don't blindly preserve):** the **Breathing Hub redesign is the one piece the developer never verified** — it was the in-flight work when everything stopped. Treat it as *unproven*, not *done*: it needs an actual on-device visual/UX pass before it's trusted, and it's the most likely place a revival finds "this doesn't feel right yet."

---

## 7. Confidence log (verified vs inferred)

**Verified this session:** git shape & stall timing · NSE + widget targets compile clean on the current toolchain (0 errors) · all schemes blocked by missing watchOS 26 runtime · zero real tests · no TODO debt · 2 dead-code artifacts · dependency pins · no privacy manifest · no export-compliance key · `aps-environment=development` · docs conflicts.

**Inferred / not verified:** why it stalled (behavioral) · whether newer dependency versions exist (no registry) · GCF `nodejs24` support · **whether the main app target compiles on the beta toolchain** (Liquid Glass + MapKit reverse-geocode unverified) · whether real-device push/widget/watch/location actually works (never run) · whether full account deletion exists.

→ See `ROADMAP.md` for the phased plan to close these.
