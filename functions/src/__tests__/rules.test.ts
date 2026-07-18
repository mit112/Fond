/**
 * Firestore security rules — allow/deny coverage against the real
 * `firestore.rules` (repo root), run against the Firestore emulator via
 * `@firebase/rules-unit-testing` + the modular `firebase/firestore` client
 * SDK. Uses a projectId ("fond-rules-test") distinct from the Cloud
 * Functions suites' "demo-fond" so data stays isolated in the shared
 * emulator instance started by `firebase emulators:exec`.
 *
 * Any doc that the rules themselves would block from being written by a
 * test's own auth context is seeded via `withSecurityRulesDisabled`, which
 * bypasses rules entirely (used only to arrange state, never to assert).
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  Timestamp,
  updateDoc,
} from "firebase/firestore";
import {readFileSync} from "fs";
import * as path from "path";

const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "fond-rules-test",
    firestore: {rules: readFileSync(RULES_PATH, "utf8")},
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

/** A Timestamp for "now" — satisfies the rules' `is timestamp` checks. */
function now(): Timestamp {
  return Timestamp.now();
}

/** A Timestamp an hour in the future (pairing codes' `expiresAt`). */
function future(): Timestamp {
  return Timestamp.fromDate(new Date(Date.now() + 60 * 60 * 1000));
}

describe("users/{uid}", () => {
  test("owner can create, read, and update their own doc", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(alice, "users/alice"), {publicKey: "alice-key"})
    );
    await assertSucceeds(getDoc(doc(alice, "users/alice")));
    await assertSucceeds(
      updateDoc(doc(alice, "users/alice"), {publicKey: "alice-key-2"})
    );
  });

  test("client delete is denied", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    await setDoc(doc(alice, "users/alice"), {publicKey: "alice-key"});
    await assertFails(deleteDoc(doc(alice, "users/alice")));
  });

  test("a non-owner cannot create another user's doc", async () => {
    const intruder = testEnv.authenticatedContext("intruder").firestore();
    await assertFails(
      setDoc(doc(intruder, "users/victim"), {publicKey: "hacked"})
    );
  });

  test("a non-owner cannot update another user's existing doc", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users/alice"), {
        publicKey: "alice-key",
      });
    });
    const intruder = testEnv.authenticatedContext("intruder").firestore();
    await assertFails(
      updateDoc(doc(intruder, "users/alice"), {publicKey: "hacked"})
    );
  });

  test("a partner can read the other user's doc via partnerUid", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "users/alice"), {partnerUid: "bob"});
      await setDoc(doc(db, "users/bob"), {partnerUid: "alice"});
    });
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertSucceeds(getDoc(doc(alice, "users/bob")));
  });

  test("a signed-in user who is not the partner cannot read the doc", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "users/carol"), {partnerUid: "someone-else"});
      await setDoc(doc(db, "users/bob"), {partnerUid: "alice"});
    });
    const carol = testEnv.authenticatedContext("carol").firestore();
    await assertFails(getDoc(doc(carol, "users/bob")));
  });

  test("devices: the owner can read and write their own device doc", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(alice, "users/alice/devices/device1"), {fcmToken: "tok"})
    );
    await assertSucceeds(getDoc(doc(alice, "users/alice/devices/device1")));
  });

  test("devices: a non-owner cannot read or write another user's device doc", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users/alice/devices/device1"), {
        fcmToken: "tok",
      });
    });
    const intruder = testEnv.authenticatedContext("intruder").firestore();
    await assertFails(getDoc(doc(intruder, "users/alice/devices/device1")));
    await assertFails(
      setDoc(doc(intruder, "users/alice/devices/device1"), {
        fcmToken: "hacked",
      })
    );
  });
});

describe("codes/{code}", () => {
  test("any signed-in user can read a code", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "codes/ABC123"), {
        creatorUid: "alice",
        claimed: false,
        expiresAt: future(),
        createdAt: now(),
      });
    });
    const dave = testEnv.authenticatedContext("dave").firestore();
    await assertSucceeds(getDoc(doc(dave, "codes/ABC123")));
  });

  test("create succeeds with a valid creatorUid, claimed=false, and timestamps", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(alice, "codes/CODE1"), {
        creatorUid: "alice",
        claimed: false,
        expiresAt: future(),
        createdAt: now(),
      })
    );
  });

  test("create is denied when creatorUid does not match the caller", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(alice, "codes/CODE2"), {
        creatorUid: "bob",
        claimed: false,
        expiresAt: future(),
        createdAt: now(),
      })
    );
  });

  test("create is denied when claimed is true", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(alice, "codes/CODE3"), {
        creatorUid: "alice",
        claimed: true,
        expiresAt: future(),
        createdAt: now(),
      })
    );
  });

  test("create is denied when a required timestamp field is missing", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(alice, "codes/CODE4"), {
        creatorUid: "alice",
        claimed: false,
        createdAt: now(),
        // expiresAt omitted
      })
    );
    await assertFails(
      setDoc(doc(alice, "codes/CODE5"), {
        creatorUid: "alice",
        claimed: false,
        expiresAt: future(),
        // createdAt omitted
      })
    );
  });

  test("update can flip claimed false to true, keeping the other fields", async () => {
    const expiresAt = future();
    const createdAt = now();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "codes/CODE6"), {
        creatorUid: "alice",
        claimed: false,
        expiresAt,
        createdAt,
      });
    });
    // Any signed-in user may claim (the claimer is not the creator).
    const bob = testEnv.authenticatedContext("bob").firestore();
    await assertSucceeds(updateDoc(doc(bob, "codes/CODE6"), {claimed: true}));
  });

  test("update is denied if claiming also changes creatorUid", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "codes/CODE7"), {
        creatorUid: "alice",
        claimed: false,
        expiresAt: future(),
        createdAt: now(),
      });
    });
    const bob = testEnv.authenticatedContext("bob").firestore();
    await assertFails(
      updateDoc(doc(bob, "codes/CODE7"), {claimed: true, creatorUid: "bob"})
    );
  });

  test("update is denied when it changes another field without flipping claimed", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "codes/CODE8"), {
        creatorUid: "alice",
        claimed: false,
        expiresAt: future(),
        createdAt: now(),
      });
    });
    const bob = testEnv.authenticatedContext("bob").firestore();
    await assertFails(
      updateDoc(doc(bob, "codes/CODE8"), {expiresAt: future()})
    );
  });

  test("update is denied on an already-claimed code", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "codes/CODE9"), {
        creatorUid: "alice",
        claimed: true,
        expiresAt: future(),
        createdAt: now(),
      });
    });
    const bob = testEnv.authenticatedContext("bob").firestore();
    await assertFails(updateDoc(doc(bob, "codes/CODE9"), {claimed: true}));
  });

  test("delete is denied", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "codes/CODE10"), {
        creatorUid: "alice",
        claimed: false,
        expiresAt: future(),
        createdAt: now(),
      });
    });
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertFails(deleteDoc(doc(alice, "codes/CODE10")));
  });
});

describe("connections/{id}", () => {
  /** Seeds a connection doc bypassing rules (arrangement, not assertion). */
  async function seedConnection(
    id: string,
    overrides: Record<string, unknown> = {}
  ): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `connections/${id}`), {
        user1: "alice",
        user2: "bob",
        isActive: true,
        createdAt: now(),
        ...overrides,
      });
    });
  }

  test("both members can read the connection", async () => {
    await seedConnection("conn1");
    const alice = testEnv.authenticatedContext("alice").firestore();
    const bob = testEnv.authenticatedContext("bob").firestore();
    await assertSucceeds(getDoc(doc(alice, "connections/conn1")));
    await assertSucceeds(getDoc(doc(bob, "connections/conn1")));
  });

  test("a non-member cannot read the connection", async () => {
    await seedConnection("conn1");
    const carol = testEnv.authenticatedContext("carol").firestore();
    await assertFails(getDoc(doc(carol, "connections/conn1")));
  });

  test("create succeeds when the caller is user1 or user2, isActive=true, createdAt is a timestamp", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(alice, "connections/conn2"), {
        user1: "alice",
        user2: "bob",
        isActive: true,
        createdAt: now(),
      })
    );
  });

  test("create is denied when the caller is neither user1 nor user2", async () => {
    const carol = testEnv.authenticatedContext("carol").firestore();
    await assertFails(
      setDoc(doc(carol, "connections/conn3"), {
        user1: "alice",
        user2: "bob",
        isActive: true,
        createdAt: now(),
      })
    );
  });

  test("create is denied when isActive is not true", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(alice, "connections/conn4"), {
        user1: "alice",
        user2: "bob",
        isActive: false,
        createdAt: now(),
      })
    );
  });

  test("create is denied when createdAt is missing", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertFails(
      setDoc(doc(alice, "connections/conn5"), {
        user1: "alice",
        user2: "bob",
        isActive: true,
      })
    );
  });

  test("a member can update the connection (e.g. deactivate)", async () => {
    await seedConnection("conn6");
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertSucceeds(
      updateDoc(doc(alice, "connections/conn6"), {isActive: false})
    );
  });

  test("a non-member cannot update the connection", async () => {
    await seedConnection("conn7");
    const carol = testEnv.authenticatedContext("carol").firestore();
    await assertFails(
      updateDoc(doc(carol, "connections/conn7"), {isActive: false})
    );
  });

  test("delete is denied", async () => {
    await seedConnection("conn8");
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertFails(deleteDoc(doc(alice, "connections/conn8")));
  });

  describe("history/{entryId}", () => {
    const CONNECTION_ID = "conn-history";

    beforeEach(async () => {
      await seedConnection(CONNECTION_ID);
    });

    test("a member can create an entry for each allowed type", async () => {
      const alice = testEnv.authenticatedContext("alice").firestore();
      const allowedTypes = [
        "status",
        "message",
        "nudge",
        "heartbeat",
        "promptAnswer",
      ];
      for (const type of allowedTypes) {
        await assertSucceeds(
          addDoc(collection(alice, `connections/${CONNECTION_ID}/history`), {
            authorUid: "alice",
            type,
            timestamp: now(),
          })
        );
      }
    });

    test("create is denied with a mismatched authorUid", async () => {
      const alice = testEnv.authenticatedContext("alice").firestore();
      await assertFails(
        addDoc(collection(alice, `connections/${CONNECTION_ID}/history`), {
          authorUid: "bob",
          type: "message",
          timestamp: now(),
        })
      );
    });

    test("create is denied with an invalid type", async () => {
      const alice = testEnv.authenticatedContext("alice").firestore();
      await assertFails(
        addDoc(collection(alice, `connections/${CONNECTION_ID}/history`), {
          authorUid: "alice",
          type: "bogus",
          timestamp: now(),
        })
      );
    });

    test("create is denied for a non-member of the connection", async () => {
      const carol = testEnv.authenticatedContext("carol").firestore();
      await assertFails(
        addDoc(collection(carol, `connections/${CONNECTION_ID}/history`), {
          authorUid: "carol",
          type: "message",
          timestamp: now(),
        })
      );
    });

    test("a member can read history entries", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `connections/${CONNECTION_ID}/history/e1`),
          {authorUid: "alice", type: "message", timestamp: now()}
        );
      });
      const bob = testEnv.authenticatedContext("bob").firestore();
      await assertSucceeds(
        getDoc(doc(bob, `connections/${CONNECTION_ID}/history/e1`))
      );
    });

    test("a non-member cannot read history entries", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `connections/${CONNECTION_ID}/history/e1`),
          {authorUid: "alice", type: "message", timestamp: now()}
        );
      });
      const carol = testEnv.authenticatedContext("carol").firestore();
      await assertFails(
        getDoc(doc(carol, `connections/${CONNECTION_ID}/history/e1`))
      );
    });

    test("update is denied (append-only)", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `connections/${CONNECTION_ID}/history/e1`),
          {authorUid: "alice", type: "message", timestamp: now()}
        );
      });
      const alice = testEnv.authenticatedContext("alice").firestore();
      await assertFails(
        updateDoc(doc(alice, `connections/${CONNECTION_ID}/history/e1`), {
          type: "nudge",
        })
      );
    });

    test("delete is denied (immutable)", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `connections/${CONNECTION_ID}/history/e1`),
          {authorUid: "alice", type: "message", timestamp: now()}
        );
      });
      const alice = testEnv.authenticatedContext("alice").firestore();
      await assertFails(
        deleteDoc(doc(alice, `connections/${CONNECTION_ID}/history/e1`))
      );
    });
  });
});

describe("catch-all", () => {
  test("read and write on an unrelated path are both denied", async () => {
    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertFails(getDoc(doc(alice, "randomCollection/x")));
    await assertFails(setDoc(doc(alice, "randomCollection/x"), {foo: "bar"}));
  });
});
