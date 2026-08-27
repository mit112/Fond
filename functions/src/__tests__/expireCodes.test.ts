/**
 * expireCodes — scheduled GC of expired, unclaimed pairing codes.
 *
 * The query filters `expiresAt < now AND claimed == false`, so only the
 * expired+unclaimed code is deleted; a future code and an expired+claimed
 * code both survive.
 */
import firebaseFunctionsTest from "firebase-functions-test";
import {expireCodes} from "../expireCodes.js";
import {
  clearFirestore,
  db,
  futureTimestamp,
  pastTimestamp,
} from "./helpers.js";

const tf = firebaseFunctionsTest();
// `wrap`'s public overloads don't cover v2 scheduled functions (ScheduledEvent
// isn't a CloudEvent), so cast `wrap` to a plain unary shape. At runtime the
// function's `scheduleTrigger` routes it correctly and the handler ignores its
// event argument, so calling `run()` with no args is valid.
const run = (tf.wrap as unknown as (fn: unknown) => () => Promise<void>)(
  expireCodes
);

beforeEach(async () => {
  await clearFirestore();
});

afterAll(() => {
  tf.cleanup();
});

async function exists(codeId: string): Promise<boolean> {
  return (await db().collection("codes").doc(codeId).get()).exists;
}

test("deletes only expired, unclaimed codes", async () => {
  await db().collection("codes").doc("EXPIRD").set({
    creatorUid: "u1",
    claimed: false,
    expiresAt: pastTimestamp(),
  });
  await db().collection("codes").doc("FUTURE").set({
    creatorUid: "u2",
    claimed: false,
    expiresAt: futureTimestamp(),
  });
  await db().collection("codes").doc("CLAIMD").set({
    creatorUid: "u3",
    claimed: true,
    expiresAt: pastTimestamp(),
  });

  await run();

  // Only the expired+unclaimed code is gone.
  expect(await exists("EXPIRD")).toBe(false);
  expect(await exists("FUTURE")).toBe(true);
  expect(await exists("CLAIMD")).toBe(true);
});

test("no expired codes → no-op (nothing deleted)", async () => {
  await db().collection("codes").doc("FUTURE").set({
    creatorUid: "u2",
    claimed: false,
    expiresAt: futureTimestamp(),
  });

  await run();

  expect(await exists("FUTURE")).toBe(true);
});
