#if canImport(FirebaseFirestore)

import Foundation
import os
import WidgetKit
import FirebaseFirestore
import FirebaseAuth

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

private let logger = Logger(subsystem: "com.mitsheth.Fond", category: "Firebase")

final class FirebaseManager: Sendable {
    static let shared = FirebaseManager()
    private let db = Firestore.firestore()
    private init() {}

    // MARK: - User Document

    /// Creates or updates the user document in Firestore after sign-in.
    func ensureUserDocument(uid: String) async throws {
        let ref = db.collection(FondConstants.usersCollection).document(uid)
        let doc = try await ref.getDocument()
        if !doc.exists {
            try await ref.setData([
                "createdAt": FieldValue.serverTimestamp(),
                "lastUpdatedAt": FieldValue.serverTimestamp(),
            ])
        }
    }

    /// Updates just the encrypted display name in Firestore (for name changes in settings).
    func updateEncryptedName(uid: String, encryptedName: String) async throws {
        try await db.collection(FondConstants.usersCollection).document(uid).updateData([
            "encryptedName": encryptedName,
            "lastUpdatedAt": FieldValue.serverTimestamp(),
        ])
    }

    // MARK: - Pairing Code

    /// Generates a unique 6-character code and writes it to Firestore. Returns the code string.
    func generatePairingCode(creatorUid: String) async throws -> String {
        let code = generateUniqueCode()
        let expiresAt = Date().addingTimeInterval(
            Double(FondConstants.codeExpirationMinutes) * 60
        )
        try await db.collection(FondConstants.codesCollection).document(code).setData([
            "creatorUid": creatorUid,
            "claimed": false,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: expiresAt),
        ])
        return code
    }

    /// Looks up a code. Returns the creator's UID if valid and unclaimed, nil otherwise.
    func lookupPairingCode(_ code: String) async throws -> String? {
        let normalized = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let doc = try await db.collection(FondConstants.codesCollection)
            .document(normalized)
            .getDocument()

        guard let data = doc.data(),
              let creatorUid = data["creatorUid"] as? String,
              let claimed = data["claimed"] as? Bool,
              let expiresAt = data["expiresAt"] as? Timestamp else {
            return nil
        }
        if claimed || expiresAt.dateValue() < Date() { return nil }
        return creatorUid
    }

    // MARK: - Link / Unlink

    /// Claims the code and links two users via Cloud Function (atomic batch write).
    func linkUsers(code: String, claimerUid: String) async throws {
        #if canImport(FirebaseFunctions)
        let normalized = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let functions = Functions.functions(region: "us-central1")
        _ = try await functions.httpsCallable(FondConstants.linkUsersFunction)
            .call(["code": normalized])
        #endif
    }

    /// Calls the unlinkConnection Cloud Function to atomically disconnect both users.
    func callUnlinkConnection() async throws {
        #if canImport(FirebaseFunctions)
        let functions = Functions.functions(region: "us-central1")
        _ = try await functions
            .httpsCallable(FondConstants.unlinkConnectionFunction).call()
        #endif
        try KeychainManager.shared.deleteAllKeys()
        await clearAppGroup()
        #if os(iOS)
        WatchSyncManager.shared.syncDisconnected()
        #endif
    }

    // MARK: - Connection Status

    /// Returns the partner's UID if connected, nil otherwise.
    func checkConnection(uid: String) async throws -> String? {
        let doc = try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .getDocument()
        let partnerUid = doc.data()?["partnerUid"] as? String
        return (partnerUid?.isEmpty == false) ? partnerUid : nil
    }

    // MARK: - Key Exchange

    /// Generates a key pair, stores private key in Keychain, writes public key to Firestore.
    func publishPublicKey(uid: String) async throws {
        let publicKeyBase64 = try KeyExchangeManager.shared.generateAndStoreKeyPair()
        try await db.collection(FondConstants.usersCollection).document(uid).setData([
            "publicKey": publicKeyBase64,
        ], merge: true)
    }

    /// Fetches partner's public key and derives the shared symmetric key.
    /// Returns true if key exchange completed, false if partner hasn't published yet.
    func completeKeyExchange(partnerUid: String) async throws -> Bool {
        let doc = try await db.collection(FondConstants.usersCollection)
            .document(partnerUid)
            .getDocument()
        guard let publicKey = doc.data()?["publicKey"] as? String,
              !publicKey.isEmpty else {
            return false
        }
        try KeyExchangeManager.shared.deriveAndStoreSymmetricKey(
            partnerPublicKeyBase64: publicKey
        )
        return true
    }

    // MARK: - Status & Messaging

    /// Updates the user's encrypted status and optional message in Firestore.
    func updateStatus(
        uid: String,
        connectionId: String,
        status: UserStatus,
        message: String? = nil
    ) async throws {
        let encryptedStatus = try EncryptionManager.shared.encrypt(status.rawValue)
        var userData: [String: Any] = [
            "encryptedStatus": encryptedStatus,
            "lastUpdatedAt": FieldValue.serverTimestamp(),
        ]
        var encryptedMessage: String?
        if let message, !message.isEmpty {
            let encrypted = try EncryptionManager.shared.encrypt(message)
            userData["encryptedMessage"] = encrypted
            encryptedMessage = encrypted
        }
        try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .updateData(userData)
        try await appendHistory(
            connectionId: connectionId, authorUid: uid,
            type: .status, encryptedPayload: encryptedStatus
        )
        if let encryptedMessage {
            try await appendHistory(
                connectionId: connectionId, authorUid: uid,
                type: .message, encryptedPayload: encryptedMessage
            )
        }
        callNotifyPartner(type: message != nil ? "message" : "status")
    }

    /// Sends an encrypted message (without changing status).
    func sendMessage(
        uid: String,
        connectionId: String,
        message: String
    ) async throws {
        let encrypted = try EncryptionManager.shared.encrypt(message)
        try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .updateData([
                "encryptedMessage": encrypted,
                "lastUpdatedAt": FieldValue.serverTimestamp(),
            ])
        try await appendHistory(
            connectionId: connectionId, authorUid: uid,
            type: .message, encryptedPayload: encrypted
        )
        callNotifyPartner(type: "message")
    }

    // MARK: - Date Settings

    /// Sets the anniversary date on the connection document (shared between both partners).
    func setAnniversaryDate(connectionId: String, date: Date?) async throws {
        let ref = db.collection(FondConstants.connectionsCollection)
            .document(connectionId)
        let value: Any = date.map { Timestamp(date: $0) } ?? FieldValue.delete()
        try await ref.updateData(["anniversaryDate": value])
    }

    /// Sets the countdown date + encrypted label on the user's own document.
    func setCountdownDate(uid: String, date: Date?, label: String?) async throws {
        var data: [String: Any] = [:]
        data["countdownDate"] = date.map { Timestamp(date: $0) } ?? FieldValue.delete()
        if let label, !label.isEmpty {
            data["countdownLabel"] = try EncryptionManager.shared.encrypt(label)
        } else {
            data["countdownLabel"] = FieldValue.delete()
        }
        try await db.collection(FondConstants.usersCollection)
            .document(uid).updateData(data)
    }

    /// Listens for changes to the connection document (e.g., partner sets anniversary).
    func listenToConnection(
        connectionId: String,
        onChange: @escaping (_ anniversaryDate: Date?) -> Void
    ) -> ListenerRegistration {
        db.collection(FondConstants.connectionsCollection)
            .document(connectionId)
            .addSnapshotListener { snapshot, error in
                guard let data = snapshot?.data(), error == nil else { return }
                onChange((data["anniversaryDate"] as? Timestamp)?.dateValue())
            }
    }

    // MARK: - Location

    /// Updates the user's encrypted location in Firestore.
    func updateLocation(uid: String, encryptedLocation: String) async throws {
        try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .updateData([
                "encryptedLocation": encryptedLocation,
                "lastUpdatedAt": FieldValue.serverTimestamp(),
            ])
    }

    // MARK: - Daily Prompt

    /// Submits an encrypted prompt answer to Firestore.
    func submitPromptAnswer(
        uid: String,
        connectionId: String,
        encryptedAnswer: String
    ) async throws {
        try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .updateData([
                "encryptedPromptAnswer": encryptedAnswer,
                "lastUpdatedAt": FieldValue.serverTimestamp(),
            ])
        try await appendHistory(
            connectionId: connectionId, authorUid: uid,
            type: .promptAnswer, encryptedPayload: encryptedAnswer
        )
        callNotifyPartner(type: "promptAnswer")
    }

    // MARK: - Nudge

    /// Sends a nudge -- writes encrypted payload, logs to history, pushes to partner.
    func sendNudge(uid: String, connectionId: String) async throws {
        let encryptedPayload = try EncryptionManager.shared.encrypt("\u{1F49B}")
        try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .updateData([
                "encryptedMessage": encryptedPayload,
                "lastUpdatedAt": FieldValue.serverTimestamp(),
            ])
        try await appendHistory(
            connectionId: connectionId, authorUid: uid,
            type: .nudge, encryptedPayload: encryptedPayload
        )
        try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .updateData(["lastNudge": FieldValue.serverTimestamp()])
        callNotifyPartner(type: "nudge")
    }

    // MARK: - Heartbeat

    /// Sends an encrypted heart rate snapshot, logs to history, pushes to partner.
    func sendHeartbeat(uid: String, connectionId: String, bpm: Int) async throws {
        let encrypted = try EncryptionManager.shared.encrypt("{\"bpm\":\(bpm)}")
        try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .updateData([
                "encryptedHeartbeat": encrypted,
                "lastUpdatedAt": FieldValue.serverTimestamp(),
            ])
        try await appendHistory(
            connectionId: connectionId, authorUid: uid,
            type: .heartbeat, encryptedPayload: encrypted
        )
        callNotifyPartner(type: "heartbeat")
    }

    // MARK: - History

    private func appendHistory(
        connectionId: String,
        authorUid: String,
        type: FondMessage.EntryType,
        encryptedPayload: String
    ) async throws {
        try await db.collection(FondConstants.connectionsCollection)
            .document(connectionId)
            .collection(FondConstants.historySubcollection)
            .addDocument(data: [
                "authorUid": authorUid,
                "type": type.rawValue,
                "encryptedPayload": encryptedPayload,
                "timestamp": FieldValue.serverTimestamp(),
            ])
    }

    /// Fetches recent history entries (oldest-first) with cursor-based pagination.
    func fetchHistory(
        connectionId: String,
        limit: Int = 50,
        startAfter: DocumentSnapshot? = nil
    ) async throws -> (entries: [FondMessage], lastDocument: DocumentSnapshot?) {
        var query = db
            .collection(FondConstants.connectionsCollection)
            .document(connectionId)
            .collection(FondConstants.historySubcollection)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        if let startAfter {
            query = query.start(afterDocument: startAfter)
        }
        let snapshot = try await query.getDocuments()
        let messages = snapshot.documents.compactMap { doc -> FondMessage? in
            let data = doc.data()
            guard let authorUid = data["authorUid"] as? String,
                  let typeRaw = data["type"] as? String,
                  let type = FondMessage.EntryType(rawValue: typeRaw),
                  let encrypted = data["encryptedPayload"] as? String,
                  let ts = data["timestamp"] as? Timestamp else {
                return nil
            }
            return FondMessage(
                id: doc.documentID, authorUid: authorUid,
                type: type, encryptedPayload: encrypted,
                timestamp: ts.dateValue()
            )
        }.reversed()
        let lastDoc = snapshot.documents.count < limit
            ? nil : snapshot.documents.last
        return (Array(messages), lastDoc)
    }

    // MARK: - Real-Time Listener

    /// Callback payload from the partner listener -- groups all encrypted fields.
    struct PartnerUpdate {
        let encryptedStatus: String?
        let encryptedMessage: String?
        let encryptedName: String?
        let encryptedHeartbeat: String?
        let encryptedLocation: String?
        let encryptedPromptAnswer: String?
        let lastUpdated: Date?
        let lastNudge: Date?
    }

    /// Listens for changes to the partner's user doc.
    func listenToPartner(
        partnerUid: String,
        onChange: @escaping (PartnerUpdate) -> Void
    ) -> ListenerRegistration {
        db.collection(FondConstants.usersCollection)
            .document(partnerUid)
            .addSnapshotListener { snapshot, error in
                guard let data = snapshot?.data(), error == nil else { return }
                let lastNudge = (data["lastNudge"] as? Timestamp)?.dateValue()
                onChange(PartnerUpdate(
                    encryptedStatus: data["encryptedStatus"] as? String,
                    encryptedMessage: data["encryptedMessage"] as? String,
                    encryptedName: data["encryptedName"] as? String,
                    encryptedHeartbeat: data["encryptedHeartbeat"] as? String,
                    encryptedLocation: data["encryptedLocation"] as? String,
                    encryptedPromptAnswer: data["encryptedPromptAnswer"] as? String,
                    lastUpdated: (data["lastUpdatedAt"] as? Timestamp)?.dateValue(),
                    lastNudge: lastNudge
                ))
            }
    }

    // MARK: - User Data Fetch

    /// Fetches the current user's connection and partner data.
    func fetchUserData(
        uid: String
    ) async throws -> (connectionId: String?, partnerUid: String?) {
        let doc = try await db.collection(FondConstants.usersCollection)
            .document(uid).getDocument()
        let data = doc.data()
        return (data?["connectionId"] as? String, data?["partnerUid"] as? String)
    }

    // MARK: - Push Notification (Cloud Function)

    /// Calls the notifyPartner Cloud Function (fire-and-forget).
    func callNotifyPartner(type: String) {
        #if canImport(FirebaseFunctions)
        let functions = Functions.functions(region: "us-central1")
        functions.httpsCallable(FondConstants.notifyPartnerFunction)
            .call(["type": type]) { _, error in
                if let error {
                    logger.error("notifyPartner failed: \(error.localizedDescription)")
                }
            }
        #endif
    }

    // MARK: - App Group (Widget Data)

    /// Writes decrypted partner data to App Group UserDefaults for widgets.
    func writePartnerDataToAppGroup(
        name: String?,
        status: UserStatus?,
        message: String?,
        lastUpdated: Date?,
        heartbeatBpm: Int? = nil,
        distanceMiles: Double? = nil,
        partnerCity: String? = nil
    ) async {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else { return }
        defaults.set(name, forKey: FondConstants.partnerNameKey)
        defaults.set(status?.rawValue, forKey: FondConstants.partnerStatusKey)
        defaults.set(message, forKey: FondConstants.partnerMessageKey)
        defaults.set(lastUpdated, forKey: FondConstants.partnerLastUpdatedKey)
        defaults.set(
            ConnectionState.connected.rawValue,
            forKey: FondConstants.connectionStateKey
        )
        if let bpm = heartbeatBpm {
            defaults.set(bpm, forKey: FondConstants.partnerHeartbeatKey)
            defaults.set(Date(), forKey: FondConstants.partnerHeartbeatTimeKey)
        }
        if let miles = distanceMiles {
            defaults.set(miles, forKey: FondConstants.distanceMilesKey)
        }
        if let city = partnerCity {
            defaults.set(city, forKey: FondConstants.partnerCityKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
        await FondRelevanceUpdater.update()
    }

    // MARK: - Helpers

    /// Clears all partner data from App Group UserDefaults.
    private func clearAppGroup() async {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else { return }
        let keysToRemove = [
            FondConstants.partnerNameKey, FondConstants.partnerStatusKey,
            FondConstants.partnerMessageKey, FondConstants.partnerLastUpdatedKey,
            FondConstants.anniversaryDateKey, FondConstants.countdownDateKey,
            FondConstants.countdownLabelKey, FondConstants.distanceMilesKey,
            FondConstants.partnerCityKey, FondConstants.partnerHeartbeatKey,
            FondConstants.partnerHeartbeatTimeKey, FondConstants.partnerPromptAnswerKey,
            FondConstants.dailyPromptIdKey, FondConstants.dailyPromptTextKey,
            FondConstants.myPromptAnswerKey,
        ]
        keysToRemove.forEach { defaults.removeObject(forKey: $0) }
        defaults.set(
            ConnectionState.unpaired.rawValue,
            forKey: FondConstants.connectionStateKey
        )
        WidgetCenter.shared.reloadAllTimelines()
        await FondRelevanceUpdater.update()
    }

    private func generateUniqueCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<FondConstants.codeLength).map { _ in chars.randomElement()! })
    }
}

#endif
