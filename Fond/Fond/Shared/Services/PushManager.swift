//
//  PushManager.swift
//  Fond
//
//  FCM token management + device registration in Firestore.
//  Registers each device's tokens so the Cloud Function can fan out pushes.
//
//  Background push handling (two paths, in priority order):
//  1. FAST PATH: Decrypt partner data directly from the push payload
//     (~1ms, no network). The Cloud Function now includes encrypted fields
//     in the FCM data payload. The NSE also does this independently.
//  2. FALLBACK: Fetch from Firestore if payload is missing encrypted fields
//     (backward compat with old Cloud Function, or edge cases).
//
//  Target: Main app only.
//

#if canImport(FirebaseMessaging)

import Foundation
import os
import UIKit
import WidgetKit
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore

private let logger = Logger(subsystem: "com.mitsheth.Fond", category: "Push")

@MainActor @Observable
final class PushManager: NSObject {
    static let shared = PushManager()

    private(set) var fcmToken: String?

    override private init() {
        super.init()
    }

    // MARK: - Setup

    /// Call once after Firebase is configured (in AppDelegate).
    func configure() {
        Messaging.messaging().delegate = self
        requestNotificationPermission()
    }

    /// Requests notification permission from the user.
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                logger.error("Permission error: \(error.localizedDescription)")
                return
            }
            if granted {
                Task { @MainActor in
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    // MARK: - Device Registration

    /// Registers the current device's FCM token + widget push token in Firestore.
    /// Call on every app launch + when token refreshes.
    func registerDevice() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let token = fcmToken else { return }

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let db = Firestore.firestore()

        let platform: String = {
            #if os(watchOS)
            return "watchos"
            #elseif os(macOS)
            return "macos"
            #elseif os(visionOS)
            return "visionos"
            #else
            if UIDevice.current.userInterfaceIdiom == .pad {
                return "ipados"
            }
            return "ios"
            #endif
        }()

        // Read widget push token from App Group (written by WidgetPushHandler)
        let widgetToken = UserDefaults(suiteName: FondConstants.appGroupID)?
            .string(forKey: FondConstants.widgetPushTokenKey)

        var deviceData: [String: Any] = [
            "platform": platform,
            "fcmToken": token,
            "lastSeen": FieldValue.serverTimestamp(),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        ]

        if let widgetToken, !widgetToken.isEmpty {
            deviceData["widgetPushToken"] = widgetToken
        }

        do {
            try await db.collection(FondConstants.usersCollection)
                .document(uid)
                .collection(FondConstants.devicesSubcollection)
                .document(deviceId)
                .setData(deviceData, merge: true)
        } catch {
            logger.error("Device registration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Handle Incoming Push (Background-Safe, Async)

    /// Primary push handler — called from AppDelegate's
    /// didReceiveRemoteNotification:fetchCompletionHandler:.
    ///
    /// Tries payload-first decryption (fast, no network), falls back to
    /// Firestore fetch if the push payload doesn't contain encrypted fields.
    /// The Notification Service Extension (NSE) also decrypts from the
    /// payload independently — this handler is the belt to the NSE's suspenders.
    func handlePushDataAsync(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let type = userInfo["type"] as? String else {
            return .noData
        }

        logger.info("Background push received: type=\(type)")

        switch type {
        case "status", "message", "nudge", "heartbeat", "promptAnswer":
            // Fast path: try to decrypt directly from push payload (~1ms)
            if await decryptFromPayload(userInfo) {
                logger.info("Fast path: decrypted from push payload")
                return .newData
            }
            // Fallback: fetch from Firestore (~1-2s)
            logger.info("Falling back to Firestore fetch")
            return await refreshPartnerDataFromFirestore()
        case "unlink":
            try? KeychainManager.shared.deleteAllKeys()
            clearAppGroup()
            WidgetCenter.shared.reloadAllTimelines()
            await FondRelevanceUpdater.update()
            return .newData
        default:
            return .noData
        }
    }

    // MARK: - Fast Path: Decrypt from Push Payload

    /// Decrypts partner data directly from the push payload (~1ms, no network).
    private func decryptFromPayload(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard userInfo["encryptedName"] is String ||
              userInfo["encryptedStatus"] is String else {
            return false
        }

        let fields = decryptFields(from: userInfo)
        let distance = computeDistance(from: userInfo)

        if let encPrompt = userInfo["encryptedPromptAnswer"] as? String {
            DailyPromptManager.shared.receivePartnerAnswer(encryptedAnswer: encPrompt)
        }

        await distributePartnerData(
            fields: fields, lastUpdated: Date(),
            distanceMiles: distance, partnerCity: nil
        )

        logger.info("Payload decryption success: \(fields.name), status=\(fields.status?.rawValue ?? "nil")")
        return true
    }

    // MARK: - Fallback: Fetch from Firestore

    /// Fallback path — fetches partner's Firestore doc when payload is missing.
    private func refreshPartnerDataFromFirestore() async -> UIBackgroundFetchResult {
        guard let uid = Auth.auth().currentUser?.uid else {
            logger.warning("No authenticated user for background refresh")
            return .failed
        }

        do {
            let db = Firestore.firestore()
            let userDoc = try await db.collection(FondConstants.usersCollection)
                .document(uid).getDocument()
            guard let userData = userDoc.data(),
                  let partnerUid = userData["partnerUid"] as? String,
                  !partnerUid.isEmpty else {
                logger.warning("No partner UID found")
                return .failed
            }

            let partnerDoc = try await db.collection(FondConstants.usersCollection)
                .document(partnerUid).getDocument()
            guard let partnerData = partnerDoc.data() else {
                logger.warning("Partner document empty")
                return .failed
            }

            let fields = decryptFields(from: partnerData)
            let lastUpdated = (partnerData["lastUpdatedAt"] as? Timestamp)?.dateValue()
            let (distance, city) = await computeDistanceWithGeocode(from: partnerData)

            if let encPrompt = partnerData["encryptedPromptAnswer"] as? String {
                DailyPromptManager.shared.receivePartnerAnswer(encryptedAnswer: encPrompt)
            }

            await distributePartnerData(
                fields: fields, lastUpdated: lastUpdated,
                distanceMiles: distance, partnerCity: city
            )

            logger.info("Background refresh success: \(fields.name), status=\(fields.status?.rawValue ?? "nil")")
            return .newData
        } catch {
            logger.error("Background refresh failed: \(error.localizedDescription)")
            return .failed
        }
    }

    // MARK: - Shared Helpers

    private struct DecryptedFields {
        let name: String
        let status: UserStatus?
        let message: String?
        let heartbeatBpm: Int?
    }

    /// Decrypts name, status, message, and heartbeat from any key-value source.
    private func decryptFields(from data: [AnyHashable: Any]) -> DecryptedFields {
        let name = EncryptionManager.shared.decryptOrNil(
            data["encryptedName"] as? String
        ) ?? "Your person"

        var status: UserStatus?
        if let encStatus = data["encryptedStatus"] as? String,
           let raw = EncryptionManager.shared.decryptOrNil(encStatus) {
            status = UserStatus(rawValue: raw)
        }

        let message = EncryptionManager.shared.decryptOrNil(
            data["encryptedMessage"] as? String
        )

        var heartbeatBpm: Int?
        if let encHB = data["encryptedHeartbeat"] as? String,
           let json = EncryptionManager.shared.decryptOrNil(encHB),
           let jsonData = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            heartbeatBpm = dict["bpm"] as? Int
        }

        return DecryptedFields(name: name, status: status, message: message, heartbeatBpm: heartbeatBpm)
    }

    /// Computes distance from encrypted location (no geocode).
    private func computeDistance(from data: [AnyHashable: Any]) -> Double? {
        #if canImport(CoreLocation)
        guard let encLoc = data["encryptedLocation"] as? String,
              let locJSON = EncryptionManager.shared.decryptOrNil(encLoc),
              let locData = locJSON.data(using: .utf8),
              let locDict = try? JSONSerialization.jsonObject(with: locData) as? [String: Any],
              let partnerLat = locDict["lat"] as? Double,
              let partnerLon = locDict["lon"] as? Double,
              let myLat = LocationManager.shared.latitude,
              let myLon = LocationManager.shared.longitude else { return nil }
        return LocationManager.haversineDistance(
            lat1: myLat, lon1: myLon, lat2: partnerLat, lon2: partnerLon
        )
        #else
        return nil
        #endif
    }

    /// Computes distance and reverse geocodes partner city.
    private func computeDistanceWithGeocode(
        from data: [AnyHashable: Any]
    ) async -> (Double?, String?) {
        #if canImport(CoreLocation)
        guard let encLoc = data["encryptedLocation"] as? String,
              let locJSON = EncryptionManager.shared.decryptOrNil(encLoc),
              let locData = locJSON.data(using: .utf8),
              let locDict = try? JSONSerialization.jsonObject(with: locData) as? [String: Any],
              let partnerLat = locDict["lat"] as? Double,
              let partnerLon = locDict["lon"] as? Double,
              let myLat = LocationManager.shared.latitude,
              let myLon = LocationManager.shared.longitude else { return (nil, nil) }
        let distance = LocationManager.haversineDistance(
            lat1: myLat, lon1: myLon, lat2: partnerLat, lon2: partnerLon
        )
        let city = await LocationManager.reverseGeocode(lat: partnerLat, lon: partnerLon)
        return (distance, city)
        #else
        return (nil, nil)
        #endif
    }

    /// Writes partner data to App Group and syncs to Apple Watch.
    private func distributePartnerData(
        fields: DecryptedFields, lastUpdated: Date?,
        distanceMiles: Double?, partnerCity: String?
    ) async {
        await FirebaseManager.shared.writePartnerDataToAppGroup(
            name: fields.name, status: fields.status, message: fields.message,
            lastUpdated: lastUpdated, heartbeatBpm: fields.heartbeatBpm,
            distanceMiles: distanceMiles, partnerCity: partnerCity
        )
        #if os(iOS)
        WatchSyncManager.shared.syncPartnerData(
            name: fields.name, status: fields.status?.rawValue,
            statusEmoji: fields.status?.emoji,
            message: fields.message, lastUpdated: lastUpdated,
            heartbeatBpm: fields.heartbeatBpm, distanceMiles: distanceMiles,
            promptText: DailyPromptManager.shared.todaysPrompt?.text,
            partnerPromptAnswer: DailyPromptManager.shared.partnerAnswer
        )
        #endif
    }

    // MARK: - App Group Cleanup

    private func clearAppGroup() {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else { return }
        defaults.removeObject(forKey: FondConstants.partnerNameKey)
        defaults.removeObject(forKey: FondConstants.partnerStatusKey)
        defaults.removeObject(forKey: FondConstants.partnerMessageKey)
        defaults.removeObject(forKey: FondConstants.partnerLastUpdatedKey)
        defaults.removeObject(forKey: FondConstants.anniversaryDateKey)
        defaults.removeObject(forKey: FondConstants.countdownDateKey)
        defaults.removeObject(forKey: FondConstants.countdownLabelKey)
        defaults.removeObject(forKey: FondConstants.partnerHeartbeatKey)
        defaults.removeObject(forKey: FondConstants.partnerHeartbeatTimeKey)
        defaults.removeObject(forKey: FondConstants.distanceMilesKey)
        defaults.removeObject(forKey: FondConstants.partnerCityKey)
        defaults.removeObject(forKey: FondConstants.partnerPromptAnswerKey)
        defaults.removeObject(forKey: FondConstants.dailyPromptIdKey)
        defaults.removeObject(forKey: FondConstants.dailyPromptTextKey)
        defaults.removeObject(forKey: FondConstants.myPromptAnswerKey)
        defaults.set(ConnectionState.unpaired.rawValue, forKey: FondConstants.connectionStateKey)
    }
}

// MARK: - MessagingDelegate

extension PushManager: @preconcurrency MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        self.fcmToken = fcmToken
        Task { await registerDevice() }
    }
}

#else

// Stub for targets without FirebaseMessaging
final class PushManager: Sendable {
    static let shared = PushManager()
    private init() {}
    func configure() {}
}

#endif
