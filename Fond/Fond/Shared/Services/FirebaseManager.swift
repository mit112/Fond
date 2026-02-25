//
//  FirebaseManager.swift
//  Fond
//
//  Wrapper for all Firestore read/write operations.
//  Phase 1: Pairing (code generation, lookup, linking).
//

#if canImport(FirebaseFirestore)

import Foundation
import WidgetKit
import FirebaseFirestore
import FirebaseAuth

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

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

    // MARK: - Pairing Code Generation

    /// Generates a unique 6-character code and writes it to Firestore.
    /// Returns the code string.
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

    // MARK: - Pairing Code Lookup

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

        // Check not claimed and not expired
        if claimed || expiresAt.dateValue() < Date() {
            return nil
        }

        return creatorUid
    }

    // MARK: - Link Two Users

    /// Claims the code and links two users together via Cloud Function.
    /// The Cloud Function handles the atomic batch write (claim code + create connection
    /// + update both users' docs) — required because the claimer can't write to the
    /// creator's user doc under client-side security rules.
    func linkUsers(code: String, claimerUid: String) async throws {
        #if canImport(FirebaseFunctions)
        let normalized = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let functions = Functions.functions(region: "us-central1")
        let _ = try await functions.httpsCallable(FondConstants.linkUsersFunction)
            .call(["code": normalized])
        #endif
    }

    // MARK: - Connection Status

    /// Checks if the user is currently connected to a partner.
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

        guard let publicKey = doc.data()?["publicKey"] as? String, !publicKey.isEmpty else {
            return false // Partner hasn't published their key yet
        }

        try KeyExchangeManager.shared.deriveAndStoreSymmetricKey(partnerPublicKeyBase64: publicKey)
        return true
    }

    // MARK: - Status & Messaging

    /// Updates the user's encrypted status and optional message in Firestore.
    /// Also appends to history subcollection.
    func updateStatus(
        uid: String,
        connectionId: String,
        status: UserStatus,
        message: String? = nil
    ) async throws {
        let encryptedStatus = try EncryptionManager.shared.encrypt(status.rawValue)
        let encryptedName = try EncryptionManager.shared.encrypt(
            Auth.auth().currentUser?.displayName ?? "Unknown"
        )

        var userData: [String: Any] = [
            "encryptedStatus": encryptedStatus,
            "encryptedName": encryptedName,
            "lastUpdatedAt": FieldValue.serverTimestamp(),
        ]

        var encryptedMessage: String?
        if let message, !message.isEmpty {
            let encrypted = try EncryptionManager.shared.encrypt(message)
            userData["encryptedMessage"] = encrypted
            encryptedMessage = encrypted
        }

        // Update user doc
        try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .updateData(userData)

        // Append status to history
        try await appendHistory(
            connectionId: connectionId,
            authorUid: uid,
            type: .status,
            encryptedPayload: encryptedStatus
        )

        // Append message to history if present
        if let encryptedMessage {
            try await appendHistory(
                connectionId: connectionId,
                authorUid: uid,
                type: .message,
                encryptedPayload: encryptedMessage
            )
        }

        // Push to partner (fire-and-forget, parallel with Firestore write)
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
            connectionId: connectionId,
            authorUid: uid,
            type: .message,
            encryptedPayload: encrypted
        )

        // Push to partner
        callNotifyPartner(type: "message")
    }

    // MARK: - Date Settings

    /// Sets the anniversary date on the connection document (shared between both partners).
    /// Plaintext — not sensitive, needed for widget date math.
    func setAnniversaryDate(connectionId: String, date: Date?) async throws {
        let ref = db.collection(FondConstants.connectionsCollection).document(connectionId)
        if let date {
            try await ref.updateData([
                "anniversaryDate": Timestamp(date: date),
            ])
        } else {
            try await ref.updateData([
                "anniversaryDate": FieldValue.delete(),
            ])
        }
    }

    /// Sets the countdown date + encrypted label on the user's own document.
    /// Date is plaintext (widget math); label is encrypted (could reveal plans).
    func setCountdownDate(uid: String, date: Date?, label: String?) async throws {
        var data: [String: Any] = [:]
        if let date {
            data["countdownDate"] = Timestamp(date: date)
        } else {
            data["countdownDate"] = FieldValue.delete()
        }
        if let label, !label.isEmpty {
            let encrypted = try EncryptionManager.shared.encrypt(label)
            data["countdownLabel"] = encrypted
        } else {
            data["countdownLabel"] = FieldValue.delete()
        }
        try await db.collection(FondConstants.usersCollection).document(uid).updateData(data)
    }

    /// Listens for changes to the connection document (e.g., partner sets anniversary).
    /// Returns a ListenerRegistration that must be retained.
    func listenToConnection(
        connectionId: String,
        onChange: @escaping (_ anniversaryDate: Date?) -> Void
    ) -> ListenerRegistration {
        return db.collection(FondConstants.connectionsCollection)
            .document(connectionId)
            .addSnapshotListener { snapshot, error in
                guard let data = snapshot?.data(), error == nil else { return }
                let date = (data["anniversaryDate"] as? Timestamp)?.dateValue()
                onChange(date)
            }
    }

    // MARK: - Location

    /// Updates the user's encrypted location in Firestore.
    /// Called by LocationManager after one-shot capture + encryption.
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
    /// Writes to user doc, appends to history, and pushes to partner.
    func submitPromptAnswer(
        uid: String,
        connectionId: String,
        encryptedAnswer: String
    ) async throws {
        // Write to user doc
        try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .updateData([
                "encryptedPromptAnswer": encryptedAnswer,
                "lastUpdatedAt": FieldValue.serverTimestamp(),
            ])

        // Append to history
        try await appendHistory(
            connectionId: connectionId,
            authorUid: uid,
            type: .promptAnswer,
            encryptedPayload: encryptedAnswer
        )

        // Push to partner — silent notification
        callNotifyPartner(type: "promptAnswer")
    }

    // MARK: - Nudge ("Thinking of You")

    /// Sends a nudge — a lightweight "thinking of you" signal.
    /// Writes "💛" as the current message (reuses existing field),
    /// logs to history, and pushes to partner.
    func sendNudge(uid: String, connectionId: String) async throws {
        let encryptedPayload = try EncryptionManager.shared.encrypt("💛")

        // Update user doc — nudge replaces current message with 💛
        try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .updateData([
                "encryptedMessage": encryptedPayload,
                "lastUpdatedAt": FieldValue.serverTimestamp(),
            ])

        // Append to history
        try await appendHistory(
            connectionId: connectionId,
            authorUid: uid,
            type: .nudge,
            encryptedPayload: encryptedPayload
        )

        // Push to partner — alert notification
        callNotifyPartner(type: "nudge")
    }

    // MARK: - Heartbeat Snapshot

    /// Sends a point-in-time heart rate snapshot.
    /// Writes encrypted bpm to a dedicated field (doesn't overwrite message),
    /// logs to history, and pushes to partner.
    func sendHeartbeat(uid: String, connectionId: String, bpm: Int) async throws {
        let heartbeatJSON = "{\"bpm\":\(bpm)}"
        let encryptedHeartbeat = try EncryptionManager.shared.encrypt(heartbeatJSON)

        // Write to dedicated heartbeat field on user doc
        try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .updateData([
                "encryptedHeartbeat": encryptedHeartbeat,
                "lastUpdatedAt": FieldValue.serverTimestamp(),
            ])

        // Append to history
        try await appendHistory(
            connectionId: connectionId,
            authorUid: uid,
            type: .heartbeat,
            encryptedPayload: encryptedHeartbeat
        )

        // Push to partner — alert notification
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

    /// Fetches recent history entries, decrypts them.
    func fetchHistory(connectionId: String, limit: Int = 50) async throws -> [FondMessage] {
        let snapshot = try await db
            .collection(FondConstants.connectionsCollection)
            .document(connectionId)
            .collection(FondConstants.historySubcollection)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> FondMessage? in
            let data = doc.data()
            guard let authorUid = data["authorUid"] as? String,
                  let typeRaw = data["type"] as? String,
                  let type = FondMessage.EntryType(rawValue: typeRaw),
                  let encryptedPayload = data["encryptedPayload"] as? String,
                  let timestamp = data["timestamp"] as? Timestamp else {
                return nil
            }
            return FondMessage(
                id: doc.documentID,
                authorUid: authorUid,
                type: type,
                encryptedPayload: encryptedPayload,
                timestamp: timestamp.dateValue()
            )
        }.reversed() // Oldest first for display
    }

    // MARK: - Real-Time Listener

    /// Listens for changes to the partner's user doc.
    /// Returns a ListenerRegistration that must be retained.
    /// Callback payload from the partner listener — groups all encrypted fields.
    struct PartnerUpdate {
        let encryptedStatus: String?
        let encryptedMessage: String?
        let encryptedName: String?
        let encryptedHeartbeat: String?
        let encryptedLocation: String?
        let encryptedPromptAnswer: String?
        let lastUpdated: Date?
    }

    /// Listens for changes to the partner's user doc.
    /// Returns a ListenerRegistration that must be retained.
    func listenToPartner(
        partnerUid: String,
        onChange: @escaping (PartnerUpdate) -> Void
    ) -> ListenerRegistration {
        return db.collection(FondConstants.usersCollection)
            .document(partnerUid)
            .addSnapshotListener { snapshot, error in
                guard let data = snapshot?.data(), error == nil else { return }
                onChange(PartnerUpdate(
                    encryptedStatus: data["encryptedStatus"] as? String,
                    encryptedMessage: data["encryptedMessage"] as? String,
                    encryptedName: data["encryptedName"] as? String,
                    encryptedHeartbeat: data["encryptedHeartbeat"] as? String,
                    encryptedLocation: data["encryptedLocation"] as? String,
                    encryptedPromptAnswer: data["encryptedPromptAnswer"] as? String,
                    lastUpdated: (data["lastUpdatedAt"] as? Timestamp)?.dateValue()
                ))
            }
    }

    // MARK: - User Data Fetch

    /// Fetches the current user's full document data.
    func fetchUserData(uid: String) async throws -> (connectionId: String?, partnerUid: String?) {
        let doc = try await db.collection(FondConstants.usersCollection)
            .document(uid)
            .getDocument()
        let data = doc.data()
        return (
            connectionId: data?["connectionId"] as? String,
            partnerUid: data?["partnerUid"] as? String
        )
    }

    // MARK: - Unlink

    /// Calls the unlinkConnection Cloud Function to atomically disconnect both users.
    func callUnlinkConnection() async throws {
        #if canImport(FirebaseFunctions)
        let functions = Functions.functions(region: "us-central1")
        let _ = try await functions.httpsCallable(FondConstants.unlinkConnectionFunction).call()
        #endif

        // Local cleanup
        try KeychainManager.shared.deleteAllKeys()
        clearAppGroup()

        // Sync disconnect to Apple Watch
        #if os(iOS)
        WatchSyncManager.shared.syncDisconnected()
        #endif
    }

    /// Clears all partner data from App Group UserDefaults.
    private func clearAppGroup() {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else { return }
        defaults.removeObject(forKey: FondConstants.partnerNameKey)
        defaults.removeObject(forKey: FondConstants.partnerStatusKey)
        defaults.removeObject(forKey: FondConstants.partnerMessageKey)
        defaults.removeObject(forKey: FondConstants.partnerLastUpdatedKey)
        defaults.removeObject(forKey: FondConstants.anniversaryDateKey)
        defaults.removeObject(forKey: FondConstants.countdownDateKey)
        defaults.removeObject(forKey: FondConstants.countdownLabelKey)
        defaults.removeObject(forKey: FondConstants.distanceMilesKey)
        defaults.removeObject(forKey: FondConstants.partnerCityKey)
        defaults.removeObject(forKey: FondConstants.partnerHeartbeatKey)
        defaults.removeObject(forKey: FondConstants.partnerHeartbeatTimeKey)
        defaults.removeObject(forKey: FondConstants.partnerPromptAnswerKey)
        defaults.removeObject(forKey: FondConstants.dailyPromptIdKey)
        defaults.removeObject(forKey: FondConstants.dailyPromptTextKey)
        defaults.removeObject(forKey: FondConstants.myPromptAnswerKey)
        defaults.set(ConnectionState.unpaired.rawValue, forKey: FondConstants.connectionStateKey)

        // Reload widgets so they show "Not Connected"
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Push Notification (Cloud Function)

    /// Calls the notifyPartner Cloud Function to push to partner's devices.
    /// Runs in parallel with Firestore writes for speed.
    func callNotifyPartner(type: String) {
        #if canImport(FirebaseFunctions)
        let functions = Functions.functions(region: "us-central1")
        functions.httpsCallable(FondConstants.notifyPartnerFunction).call(["type": type]) { result, error in
            if let error {
                print("[Fond] notifyPartner failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    // MARK: - App Group (Widget Data)

    /// Writes decrypted partner data to App Group UserDefaults so widgets can read it.
    /// Also triggers a widget timeline reload so widgets pick up the new data immediately.
    func writePartnerDataToAppGroup(
        name: String?,
        status: UserStatus?,
        message: String?,
        lastUpdated: Date?,
        heartbeatBpm: Int? = nil,
        distanceMiles: Double? = nil,
        partnerCity: String? = nil
    ) {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else { return }
        defaults.set(name, forKey: FondConstants.partnerNameKey)
        defaults.set(status?.rawValue, forKey: FondConstants.partnerStatusKey)
        defaults.set(message, forKey: FondConstants.partnerMessageKey)
        defaults.set(lastUpdated, forKey: FondConstants.partnerLastUpdatedKey)
        defaults.set(ConnectionState.connected.rawValue, forKey: FondConstants.connectionStateKey)

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

        // Reload all widget timelines so they pick up the new partner data
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Helpers

    private func generateUniqueCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // No 0/O/1/I to avoid confusion
        return String((0..<FondConstants.codeLength).map { _ in
            characters.randomElement()!
        })
    }
}

// MARK: - Errors

enum PairingError: LocalizedError {
    case invalidCode
    case cannotPairWithSelf
    case alreadyConnected

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "Invalid or expired code. Ask your partner for a new one."
        case .cannotPairWithSelf: return "You can't pair with yourself."
        case .alreadyConnected: return "You're already connected to someone."
        }
    }
}

#endif
