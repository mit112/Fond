# Fond — Current Status

> Updated: July 18, 2026 — Ember Folio visual system shipped; verification-hardening test pass underway
>
> This replaces a March 5, 2026 phase-log snapshot that described a pre-redesign, pre-test-suite state of the app (Liquid Glass content cards, no `FondTests`/`functions/src/__tests__`, wider platform scope). See `docs/superpowers/` for the redesign and hardening plans that superseded it.

---

## Where Things Stand

Fond is feature-complete for its v1 scope — pairing, encrypted status/messaging, nudges, heartbeat, location distance, and daily prompts — and has been through a full visual redesign. Platform scope is **iPhone, iPad, and Apple Watch only** (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator` on every app target in `Fond.xcodeproj`): the native macOS (Catalyst) and visionOS targets described in `00-architecture-decisions.md` and `02-design-direction.md` were dropped. The iPhone widget still reaches the Mac via widget continuity; there is no dedicated Mac app target.

## Design System: Ember Folio

The "warm glass" system described in earlier docs (`02-design-direction.md`, `05-design-review-2026-07-17.md`) has been superseded by **Ember Folio** (`docs/superpowers/specs/2026-07-18-fond-ember-folio-visual-system-design.md`, implemented and visually approved 2026-07-18 — see `docs/superpowers/plans/`). Current state, verified against `Shared/Theme/`:

- Opaque `fondKeepsakeCard()` for the Now/Together card faces (`Shared/Theme/FondTheme.swift`) — no glass, blur, or gradient on content; `.fondCard()`/`GlassEffect.clear` no longer exist.
- `CardTurnContainer`/`FondFace` (`Shared/Theme/CardTurn.swift`) — the signature 3D flip gesture between the Now and Together card faces.
- Fraunces (partner name, questions) and Newsreader (shared words) editorial serif type; SF Pro for controls/metadata (`Shared/Theme/FondTypography.swift`).
- Amber is the single brand accent. Liquid Glass (`.glassEffect()`) survives only on the floating toolbar, compose bar, and send button (`fondFloatingControl`, `fondSendControl`) — never on content.
- The animated `MeshGradient` field survives only on the pre-connection onboarding/loading background (`FondOnboardingBackground`); the connected experience uses a flat `FondField`.

## Cloud Functions

Four functions are deployed (Firebase Functions v2, `us-central1`, exported from `functions/src/index.ts`): `linkUsers`, `notifyPartner`, `unlinkConnection`, `expireCodes`. `functions/src/apnsHelper.ts` is a helper module (JWT signing + direct HTTP/2 calls to APNs) imported by `notifyPartner` — it is not its own deployed function.

## Statuses

`UserStatus` (`Shared/Models/UserStatus.swift`) has 16 cases across 4 categories: Availability (4 — available, busy, away, sleeping), Mood (5 — happy, stressed, sad, excited, calm), Activity (4 — working, driving, eating, exercising), Love (3 — thinking of you, miss you, loving you).

## Test Coverage

Added during the verification-hardening pass:

- `Fond/FondTests/` — crypto primitives (AES-GCM, X25519/HKDF), `EncryptionManager`, `KeychainManager`, `KeyExchangeManager`, status degradation + daily-prompt determinism + `FondMessage` codec, countdown cross-device sync, relationship-date summary, card-turn math, Ember Folio palette contrast, Together-moment building. 37 Swift Testing tests across 12 suites + 8 XCTest UI tests, 0 failures.
- `functions/src/__tests__/` — Firebase emulator tests for `linkUsers`, `notifyPartner`, `unlinkConnection`, `expireCodes`, plus Firestore security-rules tests (`rules.test.ts`) covering owner/partner access and append-only history.

See `CLAUDE.md`/`AGENTS.md` for build and test commands.

## Local Persistence

There is no SwiftData store in the codebase (`rg 'SwiftData|@Model'` over `Fond/` returns nothing). Local/cross-target state moves through the App Group (`group.com.mitsheth.Fond`) UserDefaults bus, written by the app/NSE and read by widgets — see `00-architecture-decisions.md` §5 ("Widget Decryption") and this repo's `CLAUDE.md` "Data Sharing via App Group" section. Earlier planning docs mention a SwiftData cache; that was never implemented.

## Architecture Implemented

```
User A (iPhone)                          Firebase                         User B (iPhone)
─────────────────                       ─────────                       ─────────────────
Sign In (Apple/Google) ──────────────→ Auth ←──────────────── Sign In
Generate Code ───────────────────────→ codes/{code} ←──────── Enter Code
Publish Public Key ──────────────────→ users/{uid}/publicKey
                                                              ← Read Public Key
                                        DH Key Exchange
Encrypt(status) ─────────────────────→ users/{uid}/encryptedStatus
callNotifyPartner() ─────────────────→ Cloud Function ──→ FCM ──→ Push
                                                              ← Snapshot Listener
                                                              ← Decrypt(status)
                                                              ← Widget reads App Group
```

## What's Next

Countdown cross-device sync is resolved (self-doc listener — see `STATE_OF_PROJECT.md` §3). See `docs/01-next-steps-open-questions.md` and the verification-hardening plan (`.superpowers/sdd/`) for remaining open items, followed by attended real-device QA (widget pipeline, unlink flow, key sync) ahead of App Store submission.
