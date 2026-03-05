//
//  NotificationService.swift
//  FondNotificationService
//
//  Notification Service Extension — intercepts ALL incoming push
//  notifications before they're displayed. This is the critical path
//  for widget updates:
//
//  1. Extracts encrypted partner data from the push payload
//  2. Decrypts using the shared Keychain symmetric key (CryptoKit)
//  3. Writes plaintext to App Group UserDefaults
//  4. Reloads widget timelines via WidgetCenter
//  5. Modifies notification display text (or suppresses for silent types)
//
//  Why an NSE instead of the main app's background handler?
//  - NSE runs for every alert+mutable-content push, even when the app
//    is force-quit or the device is in Low Power Mode
//  - NSE is a separate process — not subject to app background throttling
//  - No network needed — data arrives in the push payload itself
//  - Decryption is <1ms (CryptoKit AES-256-GCM)
//
//  Requirements:
//  - Push must have "mutable-content": 1 in aps (set in notifyPartner.ts)
//  - Push must have "alert" dict in aps (NSE doesn't run for silent pushes)
//  - Entitlements must include App Group + Keychain access group
//
//  Target: FondNotificationService (Notification Service Extension)
//  Does NOT import any Firebase SDK — lightweight and fast.
//

import UserNotifications
import WidgetKit
import CryptoKit
import Foundation

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    // MARK: - Main Entry Point

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        let userInfo = request.content.userInfo

        // Extract push type (FCM data fields are at the top level of userInfo)
        guard let type = userInfo["type"] as? String else {
            // Not a Fond push — deliver as-is
            contentHandler(bestAttemptContent)
            return
        }

        NSLog("[FondNSE] Received push: type=%@", type)

        switch type {
        case "unlink":
            handleUnlink(bestAttemptContent: bestAttemptContent)

        case "status", "message", "nudge", "heartbeat", "promptAnswer":
            handlePartnerUpdate(
                type: type,
                userInfo: userInfo,
                bestAttemptContent: bestAttemptContent
            )

        default:
            // Unknown type — deliver original notification
            contentHandler(bestAttemptContent)
            return
        }

        contentHandler(bestAttemptContent)
    }

    // MARK: - Partner Update (status, message, nudge, heartbeat, promptAnswer)

    private func handlePartnerUpdate(
        type: String,
        userInfo: [AnyHashable: Any],
        bestAttemptContent: UNMutableNotificationContent
    ) {
        // 1. Load symmetric key from shared Keychain
        guard let keyData = loadSymmetricKeyFromKeychain() else {
            NSLog("[FondNSE] No symmetric key in Keychain — delivering original notification")
            // Can't decrypt — deliver with generic text. Main app handler
            // will try Firestore fallback when it wakes.
            return
        }

        let key = SymmetricKey(data: keyData)

        // 2. Extract and decrypt encrypted fields from push payload
        //    FCM data fields appear at the top level of userInfo.
        let partnerName = decryptField(userInfo["encryptedName"] as? String, using: key)
        let statusRaw = decryptField(userInfo["encryptedStatus"] as? String, using: key)
        let message = decryptField(userInfo["encryptedMessage"] as? String, using: key)

        let status: UserStatus? = statusRaw.flatMap { UserStatus(rawValue: $0) }

        // Heartbeat
        var heartbeatBpm: Int?
        if let heartbeatJSON = decryptField(userInfo["encryptedHeartbeat"] as? String, using: key),
           let data = heartbeatJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            heartbeatBpm = dict["bpm"] as? Int
        }

        // Prompt answer
        let promptAnswer = decryptField(userInfo["encryptedPromptAnswer"] as? String, using: key)

        NSLog(
            "[FondNSE] Decrypted: name=%@, status=%@, message=%@, heartbeat=%@",
            partnerName != nil ? "yes" : "no",
            statusRaw ?? "nil",
            message != nil ? "yes" : "no",
            heartbeatBpm != nil ? "\(heartbeatBpm!)" : "nil"
        )

        // 3. Write decrypted data to App Group UserDefaults
        if let defaults = UserDefaults(suiteName: FondConstants.appGroupID) {
            if let name = partnerName {
                defaults.set(name, forKey: FondConstants.partnerNameKey)
            }
            if let status {
                defaults.set(status.rawValue, forKey: FondConstants.partnerStatusKey)
            }
            // Always write message (nil clears the previous message)
            defaults.set(message, forKey: FondConstants.partnerMessageKey)
            defaults.set(Date(), forKey: FondConstants.partnerLastUpdatedKey)
            defaults.set(ConnectionState.connected.rawValue, forKey: FondConstants.connectionStateKey)

            if let bpm = heartbeatBpm {
                defaults.set(bpm, forKey: FondConstants.partnerHeartbeatKey)
                defaults.set(Date(), forKey: FondConstants.partnerHeartbeatTimeKey)
            }

            if let answer = promptAnswer {
                defaults.set(answer, forKey: FondConstants.partnerPromptAnswerKey)
            }
        }

        // 4. Reload widget timelines — data is now fresh in App Group
        WidgetCenter.shared.reloadAllTimelines()

        // 5. Modify notification content based on type
        let displayName = partnerName ?? "Your person"

        switch type {
        case "status", "promptAnswer":
            // Suppress visible notification — the widget update is enough.
            // Setting empty title+body prevents iOS from showing a banner.
            bestAttemptContent.title = ""
            bestAttemptContent.body = ""
            bestAttemptContent.sound = nil

        case "message":
            // Show decrypted message content in the notification
            bestAttemptContent.title = displayName
            if let message, !message.isEmpty {
                bestAttemptContent.body = message
            }
            // else: keep the original generic body from the push payload

        case "nudge":
            bestAttemptContent.title = displayName
            bestAttemptContent.body = "is thinking of you 💛"

        case "heartbeat":
            bestAttemptContent.title = displayName
            if let bpm = heartbeatBpm {
                bestAttemptContent.body = "sent you a heartbeat ❤️ \(bpm) bpm"
            }

        default:
            break
        }
    }

    // MARK: - Unlink

    private func handleUnlink(bestAttemptContent: UNMutableNotificationContent) {
        NSLog("[FondNSE] Handling unlink — clearing App Group data")

        if let defaults = UserDefaults(suiteName: FondConstants.appGroupID) {
            // Clear all partner data
            defaults.removeObject(forKey: FondConstants.partnerNameKey)
            defaults.removeObject(forKey: FondConstants.partnerStatusKey)
            defaults.removeObject(forKey: FondConstants.partnerMessageKey)
            defaults.removeObject(forKey: FondConstants.partnerLastUpdatedKey)
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

        WidgetCenter.shared.reloadAllTimelines()

        // Show the unlink notification as-is (title: "Fond", body: "Your connection has ended.")
    }

    // MARK: - Timeout Fallback

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension is terminated by the system.
        // Deliver whatever we have — the original notification if decryption
        // hasn't completed (it should complete in <10ms, so this is very unlikely).
        NSLog("[FondNSE] serviceExtensionTimeWillExpire — delivering best attempt")
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: - Decryption Helpers

    /// Decrypts a Base64-encoded AES-256-GCM ciphertext using the given key.
    /// Returns nil on any failure (missing field, bad data, wrong key).
    private func decryptField(_ base64Ciphertext: String?, using key: SymmetricKey) -> String? {
        guard let ciphertext = base64Ciphertext,
              !ciphertext.isEmpty,
              let combined = Data(base64Encoded: ciphertext) else {
            return nil
        }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            NSLog("[FondNSE] Decryption failed: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Keychain Access

    /// Loads the shared symmetric key from the Keychain.
    /// Uses the same access group and service name as the main app and widget.
    private func loadSymmetricKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: FondConstants.keychainServiceName,
            kSecAttrAccount as String: "com.mitsheth.Fond.symmetricKey",
            kSecAttrAccessGroup as String: FondConstants.keychainAccessGroup,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status != errSecSuccess {
            NSLog("[FondNSE] Keychain load failed: status=%d", status)
            return nil
        }

        return result as? Data
    }
}
