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

    private override init() {
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

        let deviceId = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
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

    /// Decrypts partner data directly from the push payload without any
    /// network calls. Returns true if the payload contained encrypted fields
    /// and decryption succeeded, false if fallback to Firestore is needed.
    ///
    /// The notifyPartner Cloud Function includes the caller's encrypted
    /// fields in the FCM data payload. FCM delivers these as top-level
    /// keys in userInfo (not nested under "data").
    private func decryptFromPayload(_ userInfo: [AnyHashable: Any]) async -> Bool {
        // Check if payload contains encrypted fields (new Cloud Function format)
        guard userInfo["encryptedName"] is String ||
              userInfo["encryptedStatus"] is String else {
            return false
        }

        // Decrypt all available fields
        let name = EncryptionManager.shared.decryptOrNil(
            userInfo["encryptedName"] as? String
        ) ?? "Your person"

        var status: UserStatus?
        if let encStatus = userInfo["encryptedStatus"] as? String,
           let statusRaw = EncryptionManager.shared.decryptOrNil(encStatus) {
            status = UserStatus(rawValue: statusRaw)
        }

        let message = EncryptionManager.shared.decryptOrNil(
            userInfo["encryptedMessage"] as? String
        )

        // Heartbeat
        var heartbeatBpm: Int?
        if let encHB = userInfo["encryptedHeartbeat"] as? String,
           let json = EncryptionManager.shared.decryptOrNil(encHB),
           let jsonData = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            heartbeatBpm = dict["bpm"] as? Int
        }

        // Location + distance
        var distanceMiles: Double?
        var partnerCity: String?
        #if canImport(CoreLocation)
        if let encLoc = userInfo["encryptedLocation"] as? String,
           let locJSON = EncryptionManager.shared.decryptOrNil(encLoc),
           let locData = locJSON.data(using: .utf8),
           let locDict = try? JSONSerialization.jsonObject(with: locData) as? [String: Any],
           let partnerLat = locDict["lat"] as? Double,
           let partnerLon = locDict["lon"] as? Double,
           let myLat = LocationManager.shared.latitude,
           let myLon = LocationManager.shared.longitude {
            distanceMiles = LocationManager.haversineDistance(
                lat1: myLat, lon1: myLon,
                lat2: partnerLat, lon2: partnerLon
            )
            // Note: reverse geocode is async and we're sync here.
            // Distance is written; city will be picked up by ConnectedView listener.
        }
        #endif

        // Prompt answer
        if let encPrompt = userInfo["encryptedPromptAnswer"] as? String {
            DailyPromptManager.shared.receivePartnerAnswer(
                encryptedAnswer: encPrompt
            )
        }

        // Write to App Group (this also calls reloadAllTimelines)
        await FirebaseManager.shared.writePartnerDataToAppGroup(
            name: name,
            status: status,
            message: message,
            lastUpdated: Date(),
            heartbeatBpm: heartbeatBpm,
            distanceMiles: distanceMiles,
            partnerCity: partnerCity
        )

        // Sync to Apple Watch
        #if os(iOS)
        WatchSyncManager.shared.syncPartnerData(
            name: name,
            status: status?.rawValue,
            statusEmoji: status?.emoji,
            message: message,
            lastUpdated: Date(),
            heartbeatBpm: heartbeatBpm,
            distanceMiles: distanceMiles,
            promptText: DailyPromptManager.shared.todaysPrompt?.text,
            partnerPromptAnswer: DailyPromptManager.shared.partnerAnswer
        )
        #endif

        logger.info("Payload decryption success: \(name), status=\(status?.rawValue ?? "nil")")
        return true
    }

    // MARK: - Fallback: Fetch from Firestore

    /// Fallback path — fetches partner's latest Firestore doc, decrypts all
    /// fields, writes to App Group, and triggers widget reload.
    /// Only used when the push payload doesn't contain encrypted fields
    /// (old Cloud Function version or edge cases).
    private func refreshPartnerDataFromFirestore() async -> UIBackgroundFetchResult {
        guard let uid = Auth.auth().currentUser?.uid else {
            logger.warning("No authenticated user for background refresh")
            return .failed
        }

        do {
            let db = Firestore.firestore()

            // 1. Get partner UID from our own user doc
            let userDoc = try await db.collection(FondConstants.usersCollection)
                .document(uid)
                .getDocument()
            guard let userData = userDoc.data(),
                  let partnerUid = userData["partnerUid"] as? String,
                  !partnerUid.isEmpty else {
                logger.warning("No partner UID found")
                return .failed
            }

            // 2. Fetch partner's latest document
            let partnerDoc = try await db.collection(FondConstants.usersCollection)
                .document(partnerUid)
                .getDocument()
            guard let partnerData = partnerDoc.data() else {
                logger.warning("Partner document empty")
                return .failed
            }

            // 3. Decrypt all partner fields
            let name = EncryptionManager.shared.decryptOrNil(
                partnerData["encryptedName"] as? String
            ) ?? "Your person"

            var status: UserStatus?
            if let encStatus = partnerData["encryptedStatus"] as? String,
               let statusRaw = EncryptionManager.shared.decryptOrNil(encStatus) {
                status = UserStatus(rawValue: statusRaw)
            }

            let message = EncryptionManager.shared.decryptOrNil(
                partnerData["encryptedMessage"] as? String
            )

            let lastUpdated = (partnerData["lastUpdatedAt"] as? Timestamp)?.dateValue()

            // Parse heartbeat if present
            var heartbeatBpm: Int?
            if let encHB = partnerData["encryptedHeartbeat"] as? String,
               let json = EncryptionManager.shared.decryptOrNil(encHB),
               let jsonData = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                heartbeatBpm = dict["bpm"] as? Int
            }

            // Parse location + compute distance if available
            var distanceMiles: Double?
            var partnerCity: String?
            #if canImport(CoreLocation)
            if let encLoc = partnerData["encryptedLocation"] as? String,
               let locJSON = EncryptionManager.shared.decryptOrNil(encLoc),
               let locData = locJSON.data(using: .utf8),
               let locDict = try? JSONSerialization.jsonObject(with: locData) as? [String: Any],
               let partnerLat = locDict["lat"] as? Double,
               let partnerLon = locDict["lon"] as? Double,
               let myLat = LocationManager.shared.latitude,
               let myLon = LocationManager.shared.longitude {
                distanceMiles = LocationManager.haversineDistance(
                    lat1: myLat, lon1: myLon,
                    lat2: partnerLat, lon2: partnerLon
                )
                partnerCity = await LocationManager.reverseGeocode(
                    lat: partnerLat, lon: partnerLon
                )
            }
            #endif

            // Parse prompt answer if present
            if let encPrompt = partnerData["encryptedPromptAnswer"] as? String {
                DailyPromptManager.shared.receivePartnerAnswer(
                    encryptedAnswer: encPrompt
                )
            }

            // 4. Write decrypted data to App Group (this also calls reloadAllTimelines)
            await FirebaseManager.shared.writePartnerDataToAppGroup(
                name: name,
                status: status,
                message: message,
                lastUpdated: lastUpdated,
                heartbeatBpm: heartbeatBpm,
                distanceMiles: distanceMiles,
                partnerCity: partnerCity
            )

            // 5. Sync to Apple Watch if available
            #if os(iOS)
            WatchSyncManager.shared.syncPartnerData(
                name: name,
                status: status?.rawValue,
                statusEmoji: status?.emoji,
                message: message,
                lastUpdated: lastUpdated,
                heartbeatBpm: heartbeatBpm,
                distanceMiles: distanceMiles,
                promptText: DailyPromptManager.shared.todaysPrompt?.text,
                partnerPromptAnswer: DailyPromptManager.shared.partnerAnswer
            )
            #endif

            logger.info("Background refresh success: \(name), status=\(status?.rawValue ?? "nil")")
            return .newData
        } catch {
            logger.error("Background refresh failed: \(error.localizedDescription)")
            return .failed
        }
    }

    // MARK: - Handle Incoming Push (Legacy sync — used when app is foregrounded)
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
