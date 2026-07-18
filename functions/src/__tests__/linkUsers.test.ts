/**
 * linkUsers — the atomic pairing transaction.
 *
 * Seeds Firestore via the Admin SDK (bypasses security rules), then invokes
 * the wrapped v2 callable against the Firestore emulator and asserts the
 * transactional outcome + HttpsError codes for each precondition failure.
 */
import firebaseFunctionsTest from "firebase-functions-test";
import {Timestamp} from "firebase-admin/firestore";
import {linkUsers} from "../linkUsers.js";
import {
  clearFirestore,
  db,
  futureTimestamp,
  pastTimestamp,
} from "./helpers.js";

const tf = firebaseFunctionsTest();

/** Typed view over the wrapped callable: invoke with {data, auth}. */
const call = tf.wrap(linkUsers) as unknown as (req: {
  data: {code?: unknown};
  auth?: {uid: string};
}) => Promise<{success: boolean; connectionId: string; partnerUid: string}>;

const CODE = "ABC123";

/** Seeds a pairing code doc. */
async function seedCode(overrides: Record<string, unknown> = {}): Promise<void> {
  await db()
    .collection("codes")
    .doc(CODE)
    .set({
      creatorUid: "userA",
      claimed: false,
      expiresAt: futureTimestamp(),
      createdAt: Timestamp.now(),
      ...overrides,
    });
}

/** Seeds a user doc. */
async function seedUser(
  uid: string,
  data: Record<string, unknown> = {}
): Promise<void> {
  await db().collection("users").doc(uid).set(data);
}

beforeEach(async () => {
  await clearFirestore();
});

afterAll(() => {
  tf.cleanup();
});

test("happy path: links two users on a valid unclaimed code", async () => {
  await seedCode();
  await seedUser("userA");
  await seedUser("userB");

  const res = await call({data: {code: CODE}, auth: {uid: "userB"}});

  // Return shape
  expect(res.success).toBe(true);
  expect(typeof res.connectionId).toBe("string");
  expect(res.connectionId.length).toBeGreaterThan(0);
  expect(res.partnerUid).toBe("userA");

  // Connection document
  const connSnap = await db()
    .collection("connections")
    .doc(res.connectionId)
    .get();
  expect(connSnap.exists).toBe(true);
  const conn = connSnap.data()!;
  expect(conn.user1).toBe("userA");
  expect(conn.user2).toBe("userB");
  expect(conn.isActive).toBe(true);

  // Both user docs gain connectionId + partnerUid
  const a = (await db().collection("users").doc("userA").get()).data()!;
  expect(a.connectionId).toBe(res.connectionId);
  expect(a.partnerUid).toBe("userB");
  const b = (await db().collection("users").doc("userB").get()).data()!;
  expect(b.connectionId).toBe(res.connectionId);
  expect(b.partnerUid).toBe("userA");

  // Code marked claimed
  const codeSnap = await db().collection("codes").doc(CODE).get();
  expect(codeSnap.data()!.claimed).toBe(true);
});

test("expired unclaimed code → deadline-exceeded", async () => {
  await seedCode({expiresAt: pastTimestamp()});
  await seedUser("userA");
  await seedUser("userB");

  await expect(
    call({data: {code: CODE}, auth: {uid: "userB"}})
  ).rejects.toMatchObject({code: "deadline-exceeded"});

  // No connection created, code left unclaimed
  const codeSnap = await db().collection("codes").doc(CODE).get();
  expect(codeSnap.data()!.claimed).toBe(false);
  const conns = await db().collection("connections").get();
  expect(conns.empty).toBe(true);
});

test("self-pair (creator claims own code) → invalid-argument", async () => {
  await seedCode();
  await seedUser("userA");

  await expect(
    call({data: {code: CODE}, auth: {uid: "userA"}})
  ).rejects.toMatchObject({code: "invalid-argument"});
});

test("creator already connected → failed-precondition", async () => {
  await seedCode();
  await seedUser("userA", {partnerUid: "userX", connectionId: "old"});
  await seedUser("userB");

  await expect(
    call({data: {code: CODE}, auth: {uid: "userB"}})
  ).rejects.toMatchObject({code: "failed-precondition"});
});

test("claimer already connected → failed-precondition", async () => {
  await seedCode();
  await seedUser("userA");
  await seedUser("userB", {partnerUid: "userZ", connectionId: "old"});

  await expect(
    call({data: {code: CODE}, auth: {uid: "userB"}})
  ).rejects.toMatchObject({code: "failed-precondition"});
});

test("already-claimed code (double-claim) → already-exists", async () => {
  await seedCode({claimed: true});
  await seedUser("userA");
  await seedUser("userB");

  await expect(
    call({data: {code: CODE}, auth: {uid: "userB"}})
  ).rejects.toMatchObject({code: "already-exists"});
});
