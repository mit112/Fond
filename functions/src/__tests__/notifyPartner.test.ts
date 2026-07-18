/**
 * notifyPartner — FCM fan-out payload shaping + stale-token cleanup.
 *
 * `firebase-admin/messaging` is mocked at the jest layer (this does NOT change
 * function source/behavior) so we can assert the exact multicast payload and
 * drive a controlled BatchResponse. Firestore still runs against the emulator.
 *
 * No-secrets boundary: the partner's devices carry only an FCM `fcmToken` and
 * NO `widgetPushToken`, so the APNs/`defineSecret().value()` branch is never
 * entered — no secret is ever read.
 */
import firebaseFunctionsTest from "firebase-functions-test";
import {getMessaging} from "firebase-admin/messaging";
import {notifyPartner} from "../notifyPartner.js";
import {clearFirestore, db} from "./helpers.js";

jest.mock("firebase-admin/messaging");

const mockSendEachForMulticast = jest.fn();

const tf = firebaseFunctionsTest();
const call = tf.wrap(notifyPartner) as unknown as (req: {
  data: {type?: unknown};
  auth?: {uid: string};
}) => Promise<{
  success: boolean;
  devicesNotified: number;
  widgetsNotified: number;
}>;

beforeEach(async () => {
  await clearFirestore();
  mockSendEachForMulticast.mockReset();
  (getMessaging as jest.Mock).mockReturnValue({
    sendEachForMulticast: mockSendEachForMulticast,
  });
});

afterAll(() => {
  tf.cleanup();
});

test(
  "forwards ciphertext in FCM data + mutable-content, prunes stale token",
  async () => {
    // Caller carries encrypted fields to forward as-is (ciphertext).
    await db().collection("users").doc("userA").set({
      partnerUid: "userB",
      encryptedStatus: "CIPHER_STATUS",
      encryptedMessage: "CIPHER_MSG",
    });

    // Two partner devices, FCM only (no widgetPushToken → no secret path).
    // Doc ids sort ascending, so tokens arrive as [good, stale].
    const devices = db()
      .collection("users")
      .doc("userB")
      .collection("devices");
    await devices.doc("device-a").set({fcmToken: "good-token"});
    await devices.doc("device-b").set({fcmToken: "stale-token"});

    // Controlled BatchResponse: index 1 (stale-token) is not-registered.
    mockSendEachForMulticast.mockResolvedValue({
      successCount: 1,
      failureCount: 1,
      responses: [
        {success: true},
        {
          success: false,
          error: {code: "messaging/registration-token-not-registered"},
        },
      ],
    } as never);

    const res = await call({data: {type: "message"}, auth: {uid: "userA"}});

    expect(res).toEqual({
      success: true,
      devicesNotified: 1,
      widgetsNotified: 0,
    });

    // Payload: ciphertext forwarded in data; mutable-content for the NSE.
    expect(mockSendEachForMulticast).toHaveBeenCalledTimes(1);
    const payload = mockSendEachForMulticast.mock.calls[0][0];
    expect(payload.tokens).toEqual(["good-token", "stale-token"]);
    expect(payload.data.type).toBe("message");
    expect(payload.data.senderUid).toBe("userA");
    expect(payload.data.encryptedStatus).toBe("CIPHER_STATUS");
    expect(payload.data.encryptedMessage).toBe("CIPHER_MSG");
    expect(payload.apns.payload.aps["mutable-content"]).toBe(1);

    // Stale token pruned; good token retained.
    const remaining = await devices.get();
    expect(remaining.docs.map((d) => d.data().fcmToken)).toEqual([
      "good-token",
    ]);
  }
);

test("partner with no devices → nothing sent, count 0", async () => {
  await db().collection("users").doc("userA").set({partnerUid: "userB"});

  const res = await call({data: {type: "nudge"}, auth: {uid: "userA"}});

  expect(res).toEqual({
    success: true,
    devicesNotified: 0,
    widgetsNotified: 0,
  });
  expect(mockSendEachForMulticast).not.toHaveBeenCalled();
});

test("invalid type → invalid-argument", async () => {
  await db().collection("users").doc("userA").set({partnerUid: "userB"});

  await expect(
    call({data: {type: "bogus"}, auth: {uid: "userA"}})
  ).rejects.toMatchObject({code: "invalid-argument"});
  expect(mockSendEachForMulticast).not.toHaveBeenCalled();
});

test("caller not connected → failed-precondition", async () => {
  await db().collection("users").doc("userA").set({});

  await expect(
    call({data: {type: "message"}, auth: {uid: "userA"}})
  ).rejects.toMatchObject({code: "failed-precondition"});
});
