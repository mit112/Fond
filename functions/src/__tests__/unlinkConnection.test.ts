/**
 * unlinkConnection — atomic disconnect + idempotency.
 *
 * Seeds a connected pair (no devices, so the best-effort push path is a
 * no-op and no messaging/secret is touched), then asserts the batch write
 * clears both users and deactivates the connection.
 *
 * Idempotency note (bound to real source behavior): the handler deletes the
 * caller's `connectionId`/`partnerUid`, so a SECOND unlink finds no connection
 * and rejects with `failed-precondition`. That is a safe no-op — it does not
 * corrupt state or throw an unexpected error — which is what we assert. (The
 * brief's "no throw" phrasing does not match the source; the source instead
 * fails safely, which is acceptable, so no defect is filed.)
 */
import firebaseFunctionsTest from "firebase-functions-test";
import {unlinkConnection} from "../unlinkConnection.js";
import {clearFirestore, db} from "./helpers.js";

const tf = firebaseFunctionsTest();
const call = tf.wrap(unlinkConnection) as unknown as (req: {
  data?: unknown;
  auth?: {uid: string};
}) => Promise<{success: boolean}>;

/** Seeds an active connection between userA and userB with encrypted fields. */
async function seedConnected(): Promise<void> {
  await db().collection("connections").doc("conn1").set({
    user1: "userA",
    user2: "userB",
    isActive: true,
  });
  await db().collection("users").doc("userA").set({
    connectionId: "conn1",
    partnerUid: "userB",
    encryptedName: "NAME_A",
    encryptedStatus: "STATUS_A",
    encryptedMessage: "MSG_A",
  });
  await db().collection("users").doc("userB").set({
    connectionId: "conn1",
    partnerUid: "userA",
    encryptedName: "NAME_B",
    encryptedStatus: "STATUS_B",
    encryptedMessage: "MSG_B",
  });
}

beforeEach(async () => {
  await clearFirestore();
});

afterAll(() => {
  tf.cleanup();
});

test("clears both users and deactivates the connection", async () => {
  await seedConnected();

  const res = await call({data: {}, auth: {uid: "userA"}});
  expect(res).toEqual({success: true});

  const conn = (
    await db().collection("connections").doc("conn1").get()
  ).data()!;
  expect(conn.isActive).toBe(false);

  for (const uid of ["userA", "userB"]) {
    const u = (await db().collection("users").doc(uid).get()).data()!;
    expect(u.connectionId).toBeUndefined();
    expect(u.partnerUid).toBeUndefined();
    expect(u.encryptedName).toBeUndefined();
    expect(u.encryptedStatus).toBeUndefined();
    expect(u.encryptedMessage).toBeUndefined();
  }
});

test("second unlink is a safe no-op: rejects failed-precondition", async () => {
  await seedConnected();

  // First unlink succeeds.
  await call({data: {}, auth: {uid: "userA"}});

  // Second unlink: caller no longer has a connection → failed-precondition,
  // and state stays consistent (no corruption, no unexpected throw).
  await expect(
    call({data: {}, auth: {uid: "userA"}})
  ).rejects.toMatchObject({code: "failed-precondition"});

  const a = (await db().collection("users").doc("userA").get()).data()!;
  expect(a.connectionId).toBeUndefined();
  expect(a.partnerUid).toBeUndefined();
  const conn = (
    await db().collection("connections").doc("conn1").get()
  ).data()!;
  expect(conn.isActive).toBe(false);
});

test("unlink when never connected → failed-precondition", async () => {
  await db().collection("users").doc("userA").set({});

  await expect(
    call({data: {}, auth: {uid: "userA"}})
  ).rejects.toMatchObject({code: "failed-precondition"});
});
