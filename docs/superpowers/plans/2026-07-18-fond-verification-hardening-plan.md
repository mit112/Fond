# Fond Verification Hardening Implementation Plan (P0-backend · P1 · P2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the loop-implementable gaps on Fond's road to live — a green `functions/` toolchain, real automated tests on the E2E-crypto core / Cloud Functions / Firestore rules, and the dead-code + doc-truth cleanup — all verifiable on simulators and the Firebase emulator with **no hardware, no secrets, and no live deploy**.

**Architecture:** Fond is one Xcode project (4 targets: `Fond` app, `watchkitapp Watch App`, `widgetsExtension`, `FondNotificationService`) sharing `Fond/Fond/Shared/*`, plus an independent TypeScript Cloud Functions codebase in `functions/`. This plan adds test targets/files alongside existing code and makes minimal, behavior-preserving cleanups. It touches **no** view layer, **no** crypto/schema/function *behavior*, and **no** live systems.

**Tech Stack:** Swift 5 / SwiftUI on Xcode 27 (iOS/iPadOS/watchOS 27 SDKs), Swift Testing + XCTest, CryptoKit; TypeScript 5.7 / Node on Firebase Functions v2, `firebase-functions-test` + Firestore emulator, `@firebase/rules-unit-testing`, ESLint.

## Scope

**In scope (this plan — all 🤖 loop-implementable + verifiable):**
- **P0-backend:** `functions/` builds + lints clean; resolve the `nodejs24` / ESLint-8-EOL toolchain risks.
- **P1:** real tests for the crypto core, Cloud Functions, and Firestore rules.
- **P2:** dead-code removal + documentation-truth pass; tee up the countdown cross-device decision.

**Explicitly OUT of scope (🧑 attended — do NOT attempt here):**
- Any real-device validation, `firebase deploy`, live Firestore/APNs, secrets, or App Store Connect work (Roadmap P3–P6).
- App Store artifacts (privacy manifest, export-compliance key, screenshots). Account-deletion *implementation* may be loop-built later but its verification is attended — not in this plan.
- The redesign (Ember Folio) — already implemented, verified, approved, and integrated to `main` at `0698387`.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **Verification altitude:** the loop verifies on **simulators / the Firebase emulator / test targets only**. No physical devices, no live Firebase project (`fond-cf7f5`), no APNs, no secrets, no `firebase deploy`.
- **Toolchain:** build/test with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (Xcode 27.0, build `27A5218g`). iOS/watchOS **27.0** simulators; deployment floor stays **26.0** — do not change any deployment floor.
- **Platform scope:** Fond targets **iPhone + iPad + Apple Watch only**. Never restore `macosx`, `xros`, or `xrsimulator` to `SUPPORTED_PLATFORMS`. Do not add AppKit view-layer adaptations. Do not alter commit `58b7807`'s service-layer platform guards (`PushManager`/`AuthManager`/`LocationManager`).
- **Do NOT change behavior of:** E2E crypto, the Firestore data model/schema, Cloud Function *behavior*, App Group keys (`group.com.mitsheth.Fond`), Keychain identifiers (service/access-group `3P89U4WZAB.com.mitsheth.Fond`, tags `com.mitsheth.Fond.privateKey`/`.symmetricKey`), stored raw values, the push payload contract, or notification semantics.
- **Crypto production source is protected by default.** Tests must exercise it without modifying it. If a testability seam in `EncryptionManager`/`KeyExchangeManager` proves genuinely necessary, STOP and get Mit's approval before editing crypto source — do not refactor crypto silently.
- **Preserve raw values:** never rename `UserStatus` raw values or `FondMessage.EntryType` raw values (`status`/`message`/`nudge`/`heartbeat`/`promptAnswer`) — they are stored in Firestore/history.
- **Logging:** use `os.Logger`, never `print()`.
- **Adding a `functions/` `test` script and test deps is allowed** (test infrastructure, not function behavior). Do not change `firebase-admin`/`firebase-functions` major versions.
- **Commits:** each task ends in exactly one imperative, logical commit. **No AI attribution, no `Co-Authored-By`, no "Generated with …" lines** — inspect every commit message before committing.
- **Work location:** a fresh git worktree/branch off `main` (see the kickoff prompt). `main` is at `0698387` and pushed to `origin/main`.

---

## File Structure

### Create
- `Fond/FondTests/CryptoPrimitiveTests.swift` — pure CryptoKit AES-GCM + X25519/HKDF tests (no Keychain).
- `Fond/FondTests/KeychainManagerTests.swift` — save/load/delete round-trips (app-hosted).
- `Fond/FondTests/EncryptionManagerTests.swift` — manager round-trip + tamper + error mapping (app-hosted).
- `Fond/FondTests/KeyExchangeManagerTests.swift` — generate/derive/availability (app-hosted).
- `Fond/FondTests/StatusAndPromptTests.swift` — `UserStatus` unknown-value degradation + `DailyPromptManager` UTC rotation + `FondMessage` codec.
- `functions/src/__tests__/linkUsers.test.ts`, `notifyPartner.test.ts`, `unlinkConnection.test.ts`, `expireCodes.test.ts` — emulator-backed function tests.
- `functions/src/__tests__/rules.test.ts` — Firestore security-rules tests (`@firebase/rules-unit-testing`).
- `functions/jest.config.js` (or `mocha` config — match whatever the executor picks; Jest assumed below).

### Modify
- `functions/package.json` — add `test` script + test devDeps; resolve `engines.node`; resolve ESLint path.
- `functions/.eslintrc.js` **or** new `functions/eslint.config.js` — depending on the ESLint decision (Task 1).
- `Fond/Fond/Shared/Services/FirebaseManager.swift` — remove dead `lookupPairingCode(_:)` (Task 7).
- `Fond/Fond/Shared/Services/HeartbeatManager.swift` — remove dead `isAuthorized` assignment (~lines 71–77) (Task 7).
- `Fond/Fond/Shared/Models/FondUser.swift` — delete or wire (Task 7 decision).
- `CLAUDE.md`, `AGENTS.md` — correct the now-stale "Design System (Liquid Glass)" section + `ConnectionState` routing claim (Task 8).
- `docs/03-current-status.md`, `docs/00-architecture-decisions.md`, `README.md` — doc-truth pass (Task 8).
- `Fond/Fond.xcodeproj/project.pbxproj` — add new test files to the `FondTests` target membership (whichever tasks add Swift test files).

### Reference (read; do not assume signatures)
- Crypto: `Fond/Fond/Shared/Crypto/{EncryptionManager,KeyExchangeManager,KeychainManager}.swift` (APIs quoted in Tasks 2–4).
- Functions: `functions/src/{index,linkUsers,notifyPartner,unlinkConnection,expireCodes,apnsHelper}.ts` — **read the exact exports** before writing Task 5 tests.
- Rules: `firestore.rules` (quoted in Task 6). Emulator config: `firebase.json`.
- Models: `Fond/Fond/Shared/Models/{UserStatus,FondMessage,DailyPrompt}.swift`, `Shared/Services/DailyPromptManager.swift` — read exact signatures for Task 4.

---

### Task 1: Make the `functions/` toolchain green (build · lint · runtime)

**Files:**
- Modify: `functions/package.json`
- Modify: `functions/.eslintrc.js` (or create `functions/eslint.config.js`)

**Interfaces:**
- Produces: a clean `npm run build` and `npm run lint`, and a resolved `engines.node`, so Task 5 can run tests and P3 can eventually deploy.

- [ ] **Step 1: Establish the baseline**

Run:
```bash
cd functions && npm ci && npm run build
```
Expected: `tsc` exits 0 (record any errors). Then:
```bash
npm run lint
```
Record whether ESLint 8 + `@typescript-eslint` v5 runs clean, warns, or errors against TypeScript `^5.7.3`.

- [ ] **Step 2: Resolve the Node runtime risk (`engines.node: "24"`)**

`functions/package.json` pins `"node": "24"`. Confirm the current Google Cloud Functions (Gen2) supported runtimes from **official Firebase/GCF docs** (use the documentation-lookup tooling; do not guess). 
- If `nodejs24` is GA for deploy: leave as-is and note the confirmation.
- If not GA: change `engines.node` to `"22"`.

This is a **potential hard deploy blocker** for P3 — resolve it now. (The deploy itself is attended; only the local pin/verification is in scope.)

- [ ] **Step 3: Decide the ESLint path**

ESLint 8 is EOL and `@typescript-eslint` v5 predates TS 5.7. Pick one, guided by whether Step 1 lint was clean:
- **Option A (minimal):** keep ESLint 8 / `.eslintrc.js`, confirm `npm run lint` is clean, and pin the versions. Lowest risk; unblocks now.
- **Option B (modernize):** migrate to ESLint 9 flat config (`eslint.config.js`), bump `@typescript-eslint` to v8, drop the `--ext` flag from the `lint` script (removed in v9).

Default to **Option A** unless Step 1 lint actually fails; note the choice and rationale in the commit.

- [ ] **Step 4: Verify**

Run `npm run build && npm run lint`. Expected: both exit 0. (Lint runs in `predeploy` → it can block P3.)

- [ ] **Step 5: Commit**

```bash
git add functions/package.json functions/.eslintrc.js functions/eslint.config.js 2>/dev/null
git commit -m "chore(functions): green the build/lint toolchain and resolve node runtime"
```

---

### Task 2: Pure-primitive crypto tests (no Keychain)

**Files:**
- Create: `Fond/FondTests/CryptoPrimitiveTests.swift`
- Modify: `Fond/Fond.xcodeproj/project.pbxproj` (add file to `FondTests` membership)

**Interfaces:**
- Consumes: CryptoKit only (`AES.GCM`, `Curve25519.KeyAgreement`, `SharedSecret.hkdfDerivedSymmetricKey`). This proves the **algorithm + domain-separation constants** Fond relies on, independent of Keychain, so it is 100% deterministic and side-effect-free.
- These tests must mirror `KeyExchangeManager`'s exact parameters: HKDF `using: SHA256.self`, `salt: Data("Fond-v1".utf8)`, `sharedInfo: Data("Fond-E2E-v1".utf8)`, `outputByteCount: 32`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CryptoKit
import Foundation

struct CryptoPrimitiveTests {
    // AES-256-GCM round-trip with the combined nonce+ct+tag layout Fond stores.
    @Test func aesGcmRoundTripCombined() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("made coffee, thinking about our trip".utf8)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        let combined = try #require(sealed.combined)
        let reopened = try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key)
        #expect(reopened == plaintext)
    }

    // Tamper detection: flipping any ciphertext byte must fail authentication.
    @Test func aesGcmTamperIsRejected() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(Data("miss you".utf8), using: key)
        var combined = try #require(sealed.combined)
        combined[combined.count - 1] ^= 0x01  // corrupt the tag
        #expect(throws: (any Error).self) {
            _ = try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key)
        }
    }

    // Both partners derive the identical symmetric key (the E2E promise).
    @Test func x25519BothSidesDeriveIdenticalKey() throws {
        let a = Curve25519.KeyAgreement.PrivateKey()
        let b = Curve25519.KeyAgreement.PrivateKey()
        let keyA = try deriveKey(myPrivate: a, theirPublic: b.publicKey)
        let keyB = try deriveKey(myPrivate: b, theirPublic: a.publicKey)
        #expect(keyA == keyB)
    }

    // Domain separation: the "Fond-E2E-v1" sharedInfo must change the derived key.
    @Test func hkdfSharedInfoProvidesDomainSeparation() throws {
        let a = Curve25519.KeyAgreement.PrivateKey()
        let b = Curve25519.KeyAgreement.PrivateKey()
        let secretA = try a.sharedSecretFromKeyAgreement(with: b.publicKey)
        let v1 = secretA.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("Fond-v1".utf8), sharedInfo: Data("Fond-E2E-v1".utf8), outputByteCount: 32)
        let other = secretA.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("Fond-v1".utf8), sharedInfo: Data("Fond-E2E-v2".utf8), outputByteCount: 32)
        #expect(v1 != other)
    }

    private func deriveKey(myPrivate: Curve25519.KeyAgreement.PrivateKey,
                           theirPublic: Curve25519.KeyAgreement.PublicKey) throws -> SymmetricKey {
        try myPrivate.sharedSecretFromKeyAgreement(with: theirPublic)
            .hkdfDerivedSymmetricKey(using: SHA256.self,
                                     salt: Data("Fond-v1".utf8),
                                     sharedInfo: Data("Fond-E2E-v1".utf8),
                                     outputByteCount: 32)
    }
}
```

- [ ] **Step 2: Add the file to the `FondTests` target and run**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Fond/Fond.xcodeproj -scheme Fond \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -only-testing:FondTests/CryptoPrimitiveTests test
```
Expected: all four tests pass (they use only CryptoKit, which is already linked).

- [ ] **Step 3: Commit**

```bash
git add Fond/FondTests/CryptoPrimitiveTests.swift Fond/Fond.xcodeproj/project.pbxproj
git commit -m "test: cover AES-GCM and X25519/HKDF crypto primitives"
```

---

### Task 3: Manager-level crypto tests (Keychain-backed, app-hosted)

**Files:**
- Create: `Fond/FondTests/KeychainManagerTests.swift`, `Fond/FondTests/EncryptionManagerTests.swift`, `Fond/FondTests/KeyExchangeManagerTests.swift`
- Modify: `Fond/Fond.xcodeproj/project.pbxproj`

**Interfaces (verified from source — use exactly):**
- `KeychainManager.shared`: `savePrivateKey(_ Data) throws`, `saveSymmetricKey(_ Data) throws`, `loadPrivateKey() -> Data?`, `loadSymmetricKey() -> Data?`, `deleteAllKeys() throws`.
- `EncryptionManager.shared`: `encrypt(_ String) throws -> String`, `decrypt(_ String) throws -> String`, `decryptOrNil(_ String?) -> String?`; `EncryptionError.{missingKey,encryptionFailed,invalidCiphertext,decryptionFailed}`.
- `KeyExchangeManager.shared`: `generateAndStoreKeyPair() throws -> String` (Base64 public key), `deriveAndStoreSymmetricKey(partnerPublicKeyBase64: String) throws`, `hasSymmetricKey: Bool`, `hasPrivateKey: Bool`; `KeyExchangeError.{missingPrivateKey,invalidPublicKey}`.

> **Note:** these managers read/write the real (synchronizable) Keychain via the app's access group. The `FondTests` target is **hosted by the `Fond` app**, so it inherits the keychain entitlement. Each test MUST clean up with `deleteAllKeys()` before and after. **If synchronizable-Keychain writes prove flaky on the simulator** (possible with `kSecAttrSynchronizable = true`), STOP and report — do not weaken crypto source to make tests pass without Mit's approval (see Global Constraints).

- [ ] **Step 1: Write `KeychainManagerTests`**

```swift
import Testing
import Foundation
@testable import Fond

struct KeychainManagerTests {
    @Test func savesLoadsAndDeletesSymmetricKey() throws {
        try? KeychainManager.shared.deleteAllKeys()
        let key = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        try KeychainManager.shared.saveSymmetricKey(key)
        #expect(KeychainManager.shared.loadSymmetricKey() == key)
        try KeychainManager.shared.deleteAllKeys()
        #expect(KeychainManager.shared.loadSymmetricKey() == nil)
    }

    @Test func saveOverwritesExisting() throws {
        try? KeychainManager.shared.deleteAllKeys()
        try KeychainManager.shared.savePrivateKey(Data([0x01]))
        try KeychainManager.shared.savePrivateKey(Data([0x02]))
        #expect(KeychainManager.shared.loadPrivateKey() == Data([0x02]))
        try KeychainManager.shared.deleteAllKeys()
    }
}
```

- [ ] **Step 2: Write `EncryptionManagerTests`**

```swift
import Testing
import Foundation
import CryptoKit
@testable import Fond

struct EncryptionManagerTests {
    private func seedKey() throws {
        try? KeychainManager.shared.deleteAllKeys()
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try KeychainManager.shared.saveSymmetricKey(key)
    }

    @Test func roundTripsThroughStoredKey() throws {
        try seedKey()
        let cipher = try EncryptionManager.shared.encrypt("hello 💛")
        #expect(try EncryptionManager.shared.decrypt(cipher) == "hello 💛")
        try KeychainManager.shared.deleteAllKeys()
    }

    @Test func missingKeyThrows() throws {
        try? KeychainManager.shared.deleteAllKeys()
        #expect(throws: EncryptionError.missingKey) {
            _ = try EncryptionManager.shared.encrypt("x")
        }
    }

    @Test func invalidCiphertextThrows() throws {
        try seedKey()
        #expect(throws: EncryptionError.invalidCiphertext) {
            _ = try EncryptionManager.shared.decrypt("not-base64-@@@")
        }
        try KeychainManager.shared.deleteAllKeys()
    }

    @Test func decryptOrNilReturnsNilOnFailure() throws {
        try? KeychainManager.shared.deleteAllKeys()
        #expect(EncryptionManager.shared.decryptOrNil("anything") == nil)
        #expect(EncryptionManager.shared.decryptOrNil(nil) == nil)
    }
}
```

- [ ] **Step 3: Write `KeyExchangeManagerTests`**

```swift
import Testing
import Foundation
@testable import Fond

struct KeyExchangeManagerTests {
    @Test func generatesStoresAndReportsAvailability() throws {
        try? KeychainManager.shared.deleteAllKeys()
        let pub = try KeyExchangeManager.shared.generateAndStoreKeyPair()
        #expect(!pub.isEmpty)
        #expect(Data(base64Encoded: pub) != nil)
        #expect(KeyExchangeManager.shared.hasPrivateKey)
        try KeychainManager.shared.deleteAllKeys()
    }

    @Test func invalidPartnerKeyThrows() throws {
        try? KeychainManager.shared.deleteAllKeys()
        _ = try KeyExchangeManager.shared.generateAndStoreKeyPair()
        #expect(throws: (any Error).self) {
            try KeyExchangeManager.shared.deriveAndStoreSymmetricKey(partnerPublicKeyBase64: "!!!")
        }
        try KeychainManager.shared.deleteAllKeys()
    }

    @Test func missingPrivateKeyThrows() throws {
        try? KeychainManager.shared.deleteAllKeys()
        let throwaway = try KeyExchangeManager.shared.generateAndStoreKeyPair()  // valid public key
        try KeychainManager.shared.deleteAllKeys()  // remove the private key
        #expect(throws: KeyExchangeError.missingPrivateKey) {
            try KeyExchangeManager.shared.deriveAndStoreSymmetricKey(partnerPublicKeyBase64: throwaway)
        }
    }
}
```

- [ ] **Step 4: Add files to `FondTests`, run only these suites**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Fond/Fond.xcodeproj -scheme Fond \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -only-testing:FondTests/KeychainManagerTests \
  -only-testing:FondTests/EncryptionManagerTests \
  -only-testing:FondTests/KeyExchangeManagerTests test
```
Expected: all pass. If Keychain writes fail on the simulator, STOP and report (see the note above).

- [ ] **Step 5: Commit**

```bash
git add Fond/FondTests/KeychainManagerTests.swift Fond/FondTests/EncryptionManagerTests.swift Fond/FondTests/KeyExchangeManagerTests.swift Fond/Fond.xcodeproj/project.pbxproj
git commit -m "test: cover Keychain, Encryption, and KeyExchange managers"
```

---

### Task 4: Model & service determinism tests

**Files:**
- Create: `Fond/FondTests/StatusAndPromptTests.swift`
- Modify: `Fond/Fond.xcodeproj/project.pbxproj`

**Interfaces:** Read the exact signatures first — `UserStatus.displayInfo(forRawValue:)` (`Shared/Models/UserStatus.swift`), `DailyPromptManager` UTC-day rotation + `promptText(forID:)` (`Shared/Services/DailyPromptManager.swift`), `FondMessage` Codable (`Shared/Models/FondMessage.swift`). Do not rename any raw values.

- [ ] **Step 1: Write the tests (adjust to real signatures you read)**

```swift
import Testing
import Foundation
@testable import Fond

struct StatusAndPromptTests {
    // Unknown raw status must degrade gracefully (never crash, never lose the word).
    @Test func unknownStatusDegradesGracefully() {
        let info = UserStatus.displayInfo(forRawValue: "totally-made-up-status")
        #expect(!info.word.isEmpty)   // adjust property name to the real API
    }

    // Daily prompt rotation is deterministic per UTC day (same day → same prompt).
    @Test func promptRotationIsDeterministicPerUTCDay() {
        let day = Date(timeIntervalSince1970: 1_767_225_600)
        let a = DailyPromptManager.shared.prompt(for: day)   // adjust to real API
        let b = DailyPromptManager.shared.prompt(for: day)
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Run only this suite**

Use the Task 2 command with `-only-testing:FondTests/StatusAndPromptTests`. Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add Fond/FondTests/StatusAndPromptTests.swift Fond/Fond.xcodeproj/project.pbxproj
git commit -m "test: cover status degradation and daily-prompt determinism"
```

---

### Task 5: Cloud Functions tests (emulator + firebase-functions-test)

**Files:**
- Modify: `functions/package.json` (add `test` script + devDeps: a runner such as `jest` + `ts-jest` or `mocha`+`ts-node`, `@firebase/rules-unit-testing`; `firebase-functions-test` is already present)
- Create: `functions/jest.config.js`, `functions/src/__tests__/{linkUsers,notifyPartner,unlinkConnection,expireCodes}.test.ts`

**Interfaces:** **Read `functions/src/index.ts` and each function file first** to bind to the real exports (v2 callable/scheduled handlers). Wrap with `firebase-functions-test` and run against the **Firestore emulator** (`firebase emulators:exec` / `FIRESTORE_EMULATOR_HOST`). Do not call the live project.

- [ ] **Step 1: Add the test script + emulator wiring**

In `functions/package.json` scripts add (choose runner to match repo taste):
```json
"test": "firebase emulators:exec --only firestore \"jest --runInBand\""
```
Add `jest`, `ts-jest`, `@types/jest`, `@firebase/rules-unit-testing` to `devDependencies`. Create `functions/jest.config.js` for a `ts-jest` preset.

- [ ] **Step 2: Write `linkUsers` tests (the atomic pairing transaction)**

Cover, per `STATE_OF_PROJECT.md` §3 and the rules: **happy path** (valid unclaimed code → connection created, both users get `connectionId`/`partnerUid`, code marked claimed); **expired code** rejected; **self-pair** rejected; **already-connected** rejected; **double-claim race** (second claim fails). Example shape:

```ts
import firebaseFunctionsTest from "firebase-functions-test";
const tf = firebaseFunctionsTest();  // offline; emulator provides Firestore
import { linkUsers } from "../index";  // bind to the REAL export name you read

afterAll(() => tf.cleanup());

test("links two users on a valid unclaimed code", async () => {
  // seed code + two user docs in the emulator, then:
  const wrapped = tf.wrap(linkUsers);
  const res = await wrapped({ data: { code: "ABC123" } }, { auth: { uid: "userB" } });
  // assert connection doc created + both users updated + code.claimed == true
  expect(res).toBeDefined();
});
```

- [ ] **Step 3: Write `notifyPartner`, `unlinkConnection`, `expireCodes` tests**

- `notifyPartner`: payload shaping (ciphertext forwarded in the FCM data payload; `mutable-content:1`) and **stale FCM token cleanup**. Mock the messaging send; assert the payload + token-pruning side effects.
- `unlinkConnection`: idempotency (second unlink is a no-op, no throw) and that both users are cleared.
- `expireCodes`: deletes only codes past `expiresAt`, leaves valid ones.

- [ ] **Step 4: Verify**

```bash
cd functions && npm test
```
Expected: all suites green against the emulator.

- [ ] **Step 5: Commit**

```bash
git add functions/package.json functions/jest.config.js functions/src/__tests__
git commit -m "test(functions): cover linkUsers, notifyPartner, unlinkConnection, expireCodes"
```

---

### Task 6: Firestore security-rules tests

**Files:**
- Create: `functions/src/__tests__/rules.test.ts` (or a top-level `rules-tests/` — keep next to the emulator setup)

**Interfaces:** Use `@firebase/rules-unit-testing` against the emulator loading `firestore.rules` (quoted below). No live project.

Rules to assert (verbatim from `firestore.rules`):
- `users/{uid}`: owner can `create`/`update`/`read`; a partner (whose own doc's `partnerUid == uid`) can `read`; client `delete` denied; `devices/{id}` owner-only read/write.
- `codes/{code}`: any signed-in user can `read`; `create` requires `creatorUid == auth.uid`, `claimed == false`, timestamp fields; `update` may only flip `claimed` false→true and keep other fields; `delete` denied.
- `connections/{id}`: only members `read`/`update`; `create` requires creator ∈ {user1,user2} and `isActive == true`; `delete` denied. `history/{id}`: members `read`; `create` requires `authorUid == auth.uid`, `type in ['status','message','nudge','heartbeat','promptAnswer']`, timestamp; `update`/`delete` denied (append-only/immutable).
- Catch-all: any other path denies read+write.

- [ ] **Step 1: Write representative allow/deny tests**

```ts
import { initializeTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { setDoc, doc, updateDoc, deleteDoc } from "firebase/firestore";

let env;
beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "fond-rules-test",
    firestore: { rules: readFileSync("../firestore.rules", "utf8") },
  });
});
afterAll(() => env.cleanup());

test("history is append-only: update/delete denied", async () => {
  const uid = "userA";
  const db = env.authenticatedContext(uid).firestore();
  // seed a connection (userA member) + an entry via a privileged context, then:
  await assertFails(updateDoc(doc(db, "connections/c1/history/e1"), { type: "message" }));
  await assertFails(deleteDoc(doc(db, "connections/c1/history/e1")));
});

test("non-owner cannot write another user's doc", async () => {
  const db = env.authenticatedContext("intruder").firestore();
  await assertFails(setDoc(doc(db, "users/victim"), { publicKey: "x" }));
});
```

Add: owner read/write allowed; partner read allowed via `partnerUid`; code create validation; code claim-only update; connection member read; catch-all deny.

- [ ] **Step 2: Verify**

```bash
cd functions && firebase emulators:exec --only firestore "jest rules.test.ts"
```
Expected: all allow/deny assertions pass.

- [ ] **Step 3: Commit**

```bash
git add functions/src/__tests__/rules.test.ts
git commit -m "test: cover Firestore security rules (owner/partner/append-only/deny)"
```

---

### Task 7: Dead-code cleanup

**Files:**
- Modify: `Fond/Fond/Shared/Services/FirebaseManager.swift` (remove `lookupPairingCode(_:)`)
- Modify: `Fond/Fond/Shared/Services/HeartbeatManager.swift` (remove dead `isAuthorized` assignment, ~71–77)
- Decision: `Fond/Fond/Shared/Models/FondUser.swift` — delete **or** wire

**Interfaces:** No public behavior changes. `FondUser` is currently unreferenced (`FirebaseManager` reads Firestore via raw dictionaries).

- [ ] **Step 1: Confirm zero call sites before removing**

```bash
rg -n 'lookupPairingCode' Fond --glob '*.swift'
rg -n 'FondUser' Fond --glob '*.swift'
```
Expected: `lookupPairingCode` appears only at its definition; `FondUser` appears only in its own file.

- [ ] **Step 2: Remove `lookupPairingCode(_:)` and the dead `isAuthorized` write; decide `FondUser`**

Default decision: **delete `FondUser.swift`** (it is schema-documentation only; the schema is already documented in `AGENTS.md`/`STATE_OF_PROJECT.md`). If Mit prefers to *wire* it as the decode model, that is a larger change — defer to a separate task and keep it for now. Do not leave it dangling either way.

- [ ] **Step 3: Build + full test to prove no regression**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Fond/Fond.xcodeproj -scheme Fond \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -parallel-testing-enabled NO -test-timeouts-enabled YES test
```
Expected: `TEST SUCCEEDED`, no new warnings, no broken references.

- [ ] **Step 4: Commit**

```bash
git add -A Fond/Fond/Shared
git commit -m "chore: remove dead lookupPairingCode, isAuthorized write, and FondUser"
```

---

### Task 8: Documentation-truth pass

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`, `docs/03-current-status.md`, `docs/00-architecture-decisions.md`, `README.md`

**Interfaces:** Docs only. No code.

- [ ] **Step 1: Fix the Ember Folio design-system drift (new — created by the redesign)**

`CLAUDE.md` and `AGENTS.md` both still describe the **superseded** design system: `MeshGradient` background, `.fondCard()` with `GlassEffect.clear`, `.fondGlass()/.fondGlassInteractive()/.fondGlassPlain()`, and `FondColors` lavender/rose. The Ember Folio redesign **removed** these (flat `FondField`, opaque `fondKeepsakeCard`, control-only glass, amber-only accent, Fraunces/Newsreader type). Rewrite the "Design System" sections to match `docs/superpowers/specs/2026-07-18-fond-ember-folio-visual-system-design.md`.

- [ ] **Step 2: Fix the pre-existing drift the audit flagged**

- `CLAUDE.md`/`AGENTS.md`: `ConnectionState` does **not** route the UI (it's App-Group state only) — correct the state-machine claim.
- `docs/03-current-status.md`: stale/miscounts — rewrite or retire.
- `docs/00-architecture-decisions.md`: remove/mark **SwiftData** (documented, never built).
- `README.md`: `apnsHelper` is a helper, not a 5th Cloud Function — fix the "5 functions" claim.
- Reconcile the status count (16 statuses in 4 categories).

- [ ] **Step 3: Verify + commit**

Re-read each edited section against the code it describes. Then:
```bash
git add CLAUDE.md AGENTS.md docs/03-current-status.md docs/00-architecture-decisions.md README.md
git commit -m "docs: correct design-system, state-machine, and function-count drift"
```

---

### Task 9 (decision-gated): Countdown cross-device sync

**Files:** `Fond/Fond/Shared/Services/FirebaseManager.swift` (+ wherever `countdownDate`/`countdownLabel` are read) — only if Mit chooses to fix.

**Decision required (Mit):** `anniversaryDate` syncs both ways, but `countdownDate`/`countdownLabel` are written to the App Group locally only and stored (encrypted) in the user's own doc with no self-doc listener to read them back on a second device → countdown does not appear on a new device.
- **Option A — fix:** add a self-doc listener to read back `countdownDate`/`countdownLabel`. Loop-implementable; must preserve encrypted-field names + schema.
- **Option B — de-scope for v1:** document the limitation and move on.

- [ ] **Step 1: Get Mit's decision.** Do not guess. If A, implement behind the existing schema (no new plaintext fields, no raw-value renames) with a test; if B, add a one-paragraph note to `STATE_OF_PROJECT.md` and stop.

---

## Verify Gate (whole plan)

- `FondTests` action green on iPhone 17 Pro / iOS 27 (existing 23 + the new crypto/model suites), 0 failures.
- `cd functions && npm run build && npm run lint && npm test` all exit 0 (emulator-backed).
- Rules tests green against the emulator.
- Dead-code sweep finds no reintroduced markers; docs no longer contradict the code.
- No live systems touched; no deployment floor or platform-scope changes; crypto/schema/function-behavior/push contracts unchanged.

## Self-Review (run before handing off)

1. **Coverage:** P0-backend (Task 1), P1 crypto (Tasks 2–3), P1 models (Task 4), P1 functions (Task 5), P1 rules (Task 6), P2 hygiene (Task 7), P2 docs (Task 8), P2 countdown decision (Task 9). ✔ maps to Roadmap P0-backend/P1/P2.
2. **Placeholders:** Task 4/5 intentionally instruct reading exact signatures because those APIs weren't quoted here — the executor binds to real exports (not vague TODOs). Tasks 2–3 and 6 use verified APIs/rules verbatim.
3. **Type consistency:** crypto signatures in Task 3 match the quoted source; HKDF params in Task 2 match `KeyExchangeManager` exactly.
