//
//  WatchDataStore.swift
//  watchkitapp Watch App
//
//  Single source of truth for partner data AND outbound actions on the watch.
//
//  Receives: Partner data from iPhone via WatchConnectivity applicationContext.
//  Sends:    Actions (nudge, heartbeat) to iPhone via sendMessage / transferUserInfo.
//
//  The watch never talks to Firebase directly. All actions route through
//  the iPhone's WatchSyncManager → FirebaseManager pipeline.
//
//  Target membership: watchOS ONLY.
//

import Foundation
import os
import WatchConnectivity

private let logger = Logger(subsystem: "com.mitsheth.Fond", category: "WatchData")

@Observable
final class WatchDataStore: NSObject, WCSessionDelegate {

    // MARK: - Partner State (received from iPhone)

    var isConnected = false
    var partnerName: String?
    var partnerStatus: String?
    var partnerStatusEmoji: String?
    var partnerMessage: String?
    var partnerLastUpdated: Date?

    // Extended partner data
    var partnerHeartbeatBpm: Int?
    var partnerHeartbeatTime: Date?
    var distanceMiles: Double?
    var dailyPromptText: String?
    var partnerPromptAnswer: String?
    var anniversaryDays: Int?
    var countdownDays: Int?

    // MARK: - Send State (outbound actions)

    /// True while a send is in flight (nudge or heartbeat).
    var isSending = false

    /// Briefly true after a successful send — drives checkmark animation.
    var sendSuccess = false

    /// Non-nil if the last send failed.
    var sendError: String?

    // MARK: - Rate Limiting

    /// Timestamp of the last outbound action. Shared across nudge + heartbeat.
    private var lastSendTime: Date = .distantPast
    private static let cooldownSeconds: TimeInterval = 5

    var canSend: Bool {
        Date().timeIntervalSince(lastSendTime) >= Self.cooldownSeconds
    }

    var cooldownRemaining: Int {
        let elapsed = Date().timeIntervalSince(lastSendTime)
        let remaining = Self.cooldownSeconds - elapsed
        return remaining > 0 ? Int(remaining.rounded(.up)) : 0
    }

    // MARK: - Init & Activation

    override init() {
        super.init()
        loadFromDefaults()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Send Nudge

    /// Sends a "thinking of you" nudge to the partner via the iPhone.
    func sendNudge() {
        guard canSend else {
            sendError = "Wait \(cooldownRemaining)s"
            return
        }
        guard isConnected else {
            sendError = "Not connected"
            return
        }

        lastSendTime = Date()
        sendError = nil
        isSending = true

        let message: [String: Any] = ["action": "nudge"]
        sendToPhone(message)
    }

    // MARK: - Send Heartbeat

    /// Sends a heart rate snapshot to the partner via the iPhone.
    func sendHeartbeat(bpm: Int) {
        guard canSend else {
            sendError = "Wait \(cooldownRemaining)s"
            return
        }
        guard isConnected else {
            sendError = "Not connected"
            return
        }

        lastSendTime = Date()
        sendError = nil
        isSending = true

        let message: [String: Any] = ["action": "heartbeat", "bpm": bpm]
        sendToPhone(message)
    }

    // MARK: - WCSession Transport

    /// Sends a message to the iPhone. Tries real-time first, falls back to queued.
    private func sendToPhone(_ message: [String: Any]) {
        let session = WCSession.default

        guard session.activationState == .activated else {
            markSendComplete(success: false, error: "Watch not active")
            return
        }

        if session.isReachable {
            // Real-time: iPhone is nearby and app is reachable
            session.sendMessage(message, replyHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.markSendComplete(success: true)
                }
            }, errorHandler: { [weak self] error in
                // Real-time failed — fall back to queued delivery
                logger.warning("sendMessage failed, falling back to transferUserInfo: \(error.localizedDescription)")
                session.transferUserInfo(message)
                DispatchQueue.main.async {
                    // Treat queued send as success (will be delivered later)
                    self?.markSendComplete(success: true)
                }
            })
        } else {
            // Queued: iPhone not reachable — guaranteed delivery when it becomes available
            session.transferUserInfo(message)
            markSendComplete(success: true)
        }
    }

    /// Updates UI state after a send completes.
    private func markSendComplete(success: Bool, error: String? = nil) {
        isSending = false
        if success {
            sendSuccess = true
            sendError = nil
            // Reset success flag after animation duration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.sendSuccess = false
            }
        } else {
            sendSuccess = false
            sendError = error ?? "Failed to send"
        }
    }

    // MARK: - WCSessionDelegate: Receive from iPhone

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            let context = session.receivedApplicationContext
            if !context.isEmpty {
                DispatchQueue.main.async { self.apply(context: context) }
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.apply(context: applicationContext) }
    }

    // MARK: - Apply Context

    private func apply(context: [String: Any]) {
        let state = context["connectionState"] as? String

        if state == "disconnected" {
            isConnected = false
            partnerName = nil
            partnerStatus = nil
            partnerStatusEmoji = nil
            partnerMessage = nil
            partnerLastUpdated = nil
        } else if state == "connected" {
            isConnected = true
            partnerName = context["partnerName"] as? String
            partnerStatus = context["partnerStatus"] as? String
            partnerStatusEmoji = context["partnerStatusEmoji"] as? String
            partnerMessage = context["partnerMessage"] as? String

            if let timestamp = context["partnerLastUpdated"] as? TimeInterval {
                partnerLastUpdated = Date(timeIntervalSince1970: timestamp)
            }

            // Extended data
            if let bpm = context["partnerHeartbeat"] as? Int {
                partnerHeartbeatBpm = bpm
                partnerHeartbeatTime = Date()
            }
            if let miles = context["distanceMiles"] as? Double {
                distanceMiles = miles
            }
            dailyPromptText = context["dailyPromptText"] as? String
            partnerPromptAnswer = context["partnerPromptAnswer"] as? String
            anniversaryDays = context["anniversaryDays"] as? Int
            countdownDays = context["countdownDays"] as? Int
        }

        saveToDefaults()
    }

    // MARK: - Persistence

    private let defaults = UserDefaults.standard

    private func saveToDefaults() {
        defaults.set(isConnected, forKey: "watch_isConnected")
        defaults.set(partnerName, forKey: "watch_partnerName")
        defaults.set(partnerStatus, forKey: "watch_partnerStatus")
        defaults.set(partnerStatusEmoji, forKey: "watch_partnerStatusEmoji")
        defaults.set(partnerMessage, forKey: "watch_partnerMessage")
        if let date = partnerLastUpdated {
            defaults.set(date.timeIntervalSince1970, forKey: "watch_partnerLastUpdated")
        } else {
            defaults.removeObject(forKey: "watch_partnerLastUpdated")
        }
    }

    private func loadFromDefaults() {
        isConnected = defaults.bool(forKey: "watch_isConnected")
        partnerName = defaults.string(forKey: "watch_partnerName")
        partnerStatus = defaults.string(forKey: "watch_partnerStatus")
        partnerStatusEmoji = defaults.string(forKey: "watch_partnerStatusEmoji")
        partnerMessage = defaults.string(forKey: "watch_partnerMessage")

        let timestamp = defaults.double(forKey: "watch_partnerLastUpdated")
        partnerLastUpdated = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }
}
