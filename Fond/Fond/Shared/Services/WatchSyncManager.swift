//
//  WatchSyncManager.swift
//  Fond
//
//  Bidirectional bridge between iPhone and Apple Watch via WatchConnectivity.
//
//  Phone → Watch: updateApplicationContext (partner data, state changes).
//  Watch → Phone: sendMessage (real-time) / transferUserInfo (queued fallback).
//
//  Watch actions (nudge, heartbeat) arrive here, get routed through
//  FirebaseManager into the standard encrypted write → push pipeline.
//
//  Target membership: Fond (iOS) only. NOT watchOS, NOT widget.
//

#if os(iOS)

import Foundation
import WatchConnectivity
import FirebaseAuth

final class WatchSyncManager: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchSyncManager()

    // MARK: - Cached Connection Info

    /// Set by ConnectedView.setup() so watch actions can route to Firestore
    /// without an extra read. Cleared on disconnect.
    private var cachedUid: String?
    private var cachedConnectionId: String?

    private override init() {
        super.init()
    }

    // MARK: - Configuration

    /// Caches the current user's connection info for processing watch actions.
    /// Call from ConnectedView after fetching user data.
    func setConnectionInfo(uid: String, connectionId: String) {
        cachedUid = uid
        cachedConnectionId = connectionId
    }

    /// Clears cached connection info (call on unlink/sign-out).
    func clearConnectionInfo() {
        cachedUid = nil
        cachedConnectionId = nil
    }

    // MARK: - Activation

    /// Call once from AppDelegate on launch.
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Phone → Watch: Partner Data

    /// Sends the latest partner data to the watch.
    /// Call whenever the Firestore listener fires with new partner data.
    func syncPartnerData(
        name: String?,
        status: String?,
        statusEmoji: String?,
        message: String?,
        lastUpdated: Date?,
        heartbeatBpm: Int? = nil,
        distanceMiles: Double? = nil,
        promptText: String? = nil,
        partnerPromptAnswer: String? = nil
    ) {
        guard WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }

        var context: [String: Any] = [
            "connectionState": "connected"
        ]

        if let name        { context["partnerName"] = name }
        if let status      { context["partnerStatus"] = status }
        if let statusEmoji { context["partnerStatusEmoji"] = statusEmoji }
        if let message     { context["partnerMessage"] = message }
        if let lastUpdated { context["partnerLastUpdated"] = lastUpdated.timeIntervalSince1970 }
        if let bpm = heartbeatBpm { context["partnerHeartbeat"] = bpm }
        if let miles = distanceMiles { context["distanceMiles"] = miles }
        if let prompt = promptText { context["dailyPromptText"] = prompt }
        if let answer = partnerPromptAnswer { context["partnerPromptAnswer"] = answer }

        // Computed day counts for watch display
        if let defaults = UserDefaults(suiteName: FondConstants.appGroupID) {
            if let anniv = defaults.object(forKey: FondConstants.anniversaryDateKey) as? Date {
                let days = Calendar.current.dateComponents([.day], from: anniv, to: Date()).day ?? 0
                context["anniversaryDays"] = max(0, days)
            }
            if let countdown = defaults.object(forKey: FondConstants.countdownDateKey) as? Date {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: countdown).day ?? 0
                if days >= 0 { context["countdownDays"] = days }
            }
        }

        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("[Fond] WatchSync phone→watch failed: \(error.localizedDescription)")
        }
    }

    /// Sends a "disconnected" state to the watch (e.g., after unlinking).
    func syncDisconnected() {
        clearConnectionInfo()
        guard WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }

        do {
            try WCSession.default.updateApplicationContext([
                "connectionState": "disconnected"
            ])
        } catch {
            print("[Fond] WatchSync disconnect failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Watch → Phone: Action Handling

    /// Real-time messages from watch (when iPhone is reachable).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        processWatchAction(message)
    }

    /// Real-time messages with reply handler — reply immediately, process async.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        // Reply immediately so the watch gets fast confirmation.
        // Actual Firebase processing happens async below.
        replyHandler(["received": true])
        processWatchAction(message)
    }

    /// Queued messages from watch (delivered when iPhone becomes reachable).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        processWatchAction(userInfo)
    }

    /// Routes an incoming watch action to the appropriate Firebase pipeline.
    private func processWatchAction(_ payload: [String: Any]) {
        guard let action = payload["action"] as? String else {
            print("[Fond] WatchSync: received payload with no action key")
            return
        }

        // Resolve auth — prefer cached, fall back to live Auth
        let uid = cachedUid ?? Auth.auth().currentUser?.uid
        guard let uid else {
            print("[Fond] WatchSync: no authenticated user for action '\(action)'")
            return
        }

        switch action {
        case "nudge":
            handleNudge(uid: uid)

        case "heartbeat":
            guard let bpm = payload["bpm"] as? Int, bpm > 0 else {
                print("[Fond] WatchSync: heartbeat action missing valid bpm")
                return
            }
            handleHeartbeat(uid: uid, bpm: bpm)

        default:
            print("[Fond] WatchSync: unknown action '\(action)'")
        }
    }

    // MARK: - Nudge Processing

    private func handleNudge(uid: String) {
        Task {
            do {
                // Resolve connectionId — prefer cached, fall back to Firestore
                let connectionId = try await resolveConnectionId(uid: uid)
                try await FirebaseManager.shared.sendNudge(
                    uid: uid,
                    connectionId: connectionId
                )
                print("[Fond] WatchSync: nudge sent successfully")
            } catch {
                print("[Fond] WatchSync: nudge failed — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Heartbeat Processing

    private func handleHeartbeat(uid: String, bpm: Int) {
        Task {
            do {
                let connectionId = try await resolveConnectionId(uid: uid)
                try await FirebaseManager.shared.sendHeartbeat(
                    uid: uid,
                    connectionId: connectionId,
                    bpm: bpm
                )
                print("[Fond] WatchSync: heartbeat (\(bpm) bpm) sent successfully")
            } catch {
                print("[Fond] WatchSync: heartbeat failed — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    /// Resolves connectionId, preferring cached value to avoid extra Firestore reads.
    private func resolveConnectionId(uid: String) async throws -> String {
        if let cached = cachedConnectionId {
            return cached
        }
        // Fallback: fetch from Firestore (costs one read)
        let data = try await FirebaseManager.shared.fetchUserData(uid: uid)
        guard let connectionId = data.connectionId else {
            throw WatchSyncError.notConnected
        }
        // Cache for future actions
        cachedConnectionId = connectionId
        cachedUid = uid
        return connectionId
    }

    // MARK: - WCSessionDelegate (Required)

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("[Fond] WCSession activation error: \(error.localizedDescription)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

// MARK: - Errors

enum WatchSyncError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to a partner."
        }
    }
}

#endif
