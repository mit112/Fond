//
//  PushManager.swift
//  Fond
//
//  FCM token management + device registration in Firestore.
//  Registers each device's tokens so the Cloud Function can fan out pushes.
//
//  Target: Main app only.
//

#if canImport(FirebaseMessaging)

import Foundation
import UIKit
import WidgetKit
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore

@Observable
final class PushManager: NSObject, Sendable {
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
                print("[PushManager] Permission error: \(error.localizedDescription)")
                return
            }
            if granted {
                DispatchQueue.main.async {
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
            print("[PushManager] Device registration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Handle Incoming Push

    /// Handle silent push notification data.
    func handlePushData(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }

        switch type {
        case "status", "message":
            // Write to App Group UserDefaults so widget can read
            writeToAppGroup(userInfo)
            // Trigger widget timeline reload (backup — widget push also triggers this)
            WidgetCenter.shared.reloadAllTimelines()
        case "unlink":
            // Partner disconnected — clean up
            try? KeychainManager.shared.deleteAllKeys()
            clearAppGroup()
            WidgetCenter.shared.reloadAllTimelines()
        default:
            break
        }
    }

    // MARK: - App Group UserDefaults (for Widget)

    private func writeToAppGroup(_ userInfo: [AnyHashable: Any]) {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else { return }
        defaults.set(Date(), forKey: FondConstants.partnerLastUpdatedKey)
        // Widget will re-read from Firestore or use cached decrypted values
        // Full encrypted→decrypted pipeline happens in the app, widget reads plaintext from App Group
    }

    private func clearAppGroup() {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else { return }
        defaults.removeObject(forKey: FondConstants.partnerNameKey)
        defaults.removeObject(forKey: FondConstants.partnerStatusKey)
        defaults.removeObject(forKey: FondConstants.partnerMessageKey)
        defaults.removeObject(forKey: FondConstants.partnerLastUpdatedKey)
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
