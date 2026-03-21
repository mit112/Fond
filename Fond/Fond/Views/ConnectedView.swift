//
//  ConnectedView.swift
//  Fond
//
//  Main screen when two users are paired — the "hub" of the app.
//  Shows partner's status/message with real-time updates.
//  Lets user set their own status and send messages.
//
//  Design: Single-screen hub with animated mesh gradient background.
//  No NavigationStack, no tab bar. History + settings slide up as sheets.
//  Glass-styled controls on iOS 26, warm amber accents throughout.
//
//  Design reference: docs/02-design-direction.md
//

import SwiftUI
import WidgetKit
import FirebaseAuth
import FirebaseFirestore
import os

private let logger = Logger(subsystem: "com.mitsheth.Fond", category: "ConnectedView")

struct ConnectedView: View {
    var authManager: AuthManager
    var onDisconnect: () -> Void

    // MARK: - Partner State (from real-time listener)

    @State var partnerName: String = "..."
    @State var partnerStatus: UserStatus?
    @State var partnerMessage: String?
    @State var partnerLastUpdated: Date?

    // MARK: - My State

    @State private var myStatus: UserStatus = .available
    @State private var messageText = ""
    @State private var isSending = false
    @State private var sendSuccess = false
    @State private var lastSentMessage: String?
    @State var errorMessage: String?

    // MARK: - Rate Limiting

    @State private var lastSendTime: Date = .distantPast
    @State private var cooldownRemaining: Int = 0
    @State private var cooldownTimer: Timer?

    // MARK: - Connection Info

    @State var connectionId: String?
    @State var partnerUid: String?
    @State var listener: ListenerRegistration?
    @State var connectionListener: ListenerRegistration?

    // MARK: - Sheets

    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showStatusPicker = false

    // MARK: - Heartbeat

    @State var partnerHeartbeatBpm: Int?
    @State var partnerHeartbeatTime: Date?

    // MARK: - Distance

    @State var lastLocationCapture: Date = .distantPast
    @State var distanceMiles: Double?
    @State var partnerCity: String?

    // MARK: - Environment

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Animation

    @State var partnerDataVisible = false
    @State private var isBreathing = false

    // MARK: - Nudge

    @State private var lastNudgeTime: Date = .distantPast
    @State private var nudgeHintVisible = true
    @State private var nudgeScale: CGFloat = 1.0
    @State private var nudgeShakeOffset: CGFloat = 0

    // MARK: - Contextual Card

    @State private var lastSentMessageTime: Date?
    @State var lastNudgeReceivedTime: Date?
    @State private var showDailyPromptSheet = false

    // MARK: - Body

    var body: some View {
        ZStack {
            FondMeshGradient()
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }

            VStack(spacing: 0) {
                toolbar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 16)

                // Partner card with nudge gesture + staleness timer
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    ConnectedPartnerCard(
                        partnerName: partnerName,
                        partnerStatus: partnerStatus,
                        partnerMessage: partnerMessage,
                        partnerLastUpdated: partnerLastUpdated,
                        partnerHeartbeatBpm: partnerHeartbeatBpm,
                        partnerHeartbeatTime: partnerHeartbeatTime,
                        distanceMiles: distanceMiles,
                        partnerCity: partnerCity,
                        isBreathing: isBreathing,
                        nudgeHintVisible: nudgeHintVisible,
                        isStale: isDataStale,
                        onNudge: sendNudge
                    )
                }
                .padding(.horizontal, 24)
                .opacity(partnerDataVisible ? 1 : 0)
                .scaleEffect(partnerDataVisible ? nudgeScale : 0.95)
                .offset(x: nudgeShakeOffset)
                .onLongPressGesture(minimumDuration: 0.5) { sendNudge() }
                .accessibilityAction(named: "Send nudge") { sendNudge() }
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                        isBreathing = true
                    }
                }

                Spacer(minLength: 12)

                // Contextual card with auto-dismiss timer
                TimelineView(.periodic(from: .now, by: 10)) { _ in
                    ContextualCardView(
                        cards: activeContextualCards,
                        onTapPrompt: { showDailyPromptSheet = true }
                    )
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 10)

                // Fixed bottom bar
                ConnectedMessageInput(
                    messageText: $messageText,
                    myStatus: myStatus,
                    isSending: isSending,
                    sendSuccess: sendSuccess,
                    cooldownRemaining: cooldownRemaining,
                    errorMessage: errorMessage,
                    onSend: sendMessage,
                    onStatusTap: { showStatusPicker = true }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showStatusPicker) {
            StatusPickerSheet(currentStatus: myStatus) { newStatus in
                setStatus(newStatus)
            }
        }
        .sheet(isPresented: $showHistory) {
            if let connectionId, let uid = authManager.currentUser?.uid {
                HistoryView(connectionId: connectionId, myUid: uid)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(authManager: authManager, connectionId: connectionId, onDisconnect: onDisconnect)
        }
        .sheet(isPresented: $showDailyPromptSheet) {
            if let uid = authManager.currentUser?.uid, let cid = connectionId {
                DailyPromptCard(partnerName: partnerName, uid: uid, connectionId: cid)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .task { await setupConnection() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { nudgeHintVisible = true }
            handleScenePhaseChange(newPhase)
        }
        .onDisappear {
            listener?.remove()
            connectionListener?.remove()
            cooldownTimer?.invalidate()
            cooldownTimer = nil
        }
    }

    // MARK: - Floating Toolbar

    private var toolbar: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .foregroundStyle(FondColors.text)
                    .frame(width: 40, height: 40)
            }
            .fondGlassInteractive(in: Circle())

            Spacer()

            Text("FOND")
                .font(.caption.weight(.medium))
                .foregroundStyle(FondColors.textSecondary.opacity(0.3))
                .tracking(1.5)

            Spacer()

            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.body.weight(.medium))
                    .foregroundStyle(FondColors.text)
                    .frame(width: 40, height: 40)
            }
            .fondGlassInteractive(in: Circle())
        }
    }

    // MARK: - Stale Check

    private var isDataStale: Bool {
        guard let lastUpdated = partnerLastUpdated else { return false }
        return Date().timeIntervalSince(lastUpdated) > 3600
    }

    // MARK: - Contextual Cards

    private var activeContextualCards: [ContextualCardType] {
        var cards: [ContextualCardType] = []
        let now = Date()

        if let nudgeTime = lastNudgeReceivedTime, now.timeIntervalSince(nudgeTime) < 30 {
            cards.append(.nudgeReceived(partnerName: partnerName))
        }
        if let bpm = partnerHeartbeatBpm, let time = partnerHeartbeatTime, now.timeIntervalSince(time) < 1800 {
            cards.append(.heartbeat(bpm: bpm, time: time))
        }
        let pm = DailyPromptManager.shared
        if pm.isSubmitted && pm.partnerAnswer != nil {
            cards.append(.bothAnswered)
        } else if let prompt = pm.todaysPrompt, !pm.isSubmitted {
            cards.append(.dailyPrompt(text: prompt.text))
        }
        if let sentTime = lastSentMessageTime, now.timeIntervalSince(sentTime) < 60, let msg = lastSentMessage {
            cards.append(.sentEcho(message: msg))
        }
        return cards
    }

    // MARK: - Rate Limiting

    private var canSend: Bool {
        Date().timeIntervalSince(lastSendTime)
            >= Double(FondConstants.rateLimitSeconds)
    }

    private func startCooldownTimer() {
        let elapsed = Int(
            Date().timeIntervalSince(lastSendTime)
        )
        cooldownRemaining = max(
            FondConstants.rateLimitSeconds - elapsed,
            0
        )
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { _ in
            let elapsed = Int(
                Date().timeIntervalSince(lastSendTime)
            )
            let remaining =
                FondConstants.rateLimitSeconds - elapsed
            if remaining <= 0 {
                cooldownRemaining = 0
                cooldownTimer?.invalidate()
                cooldownTimer = nil
            } else {
                cooldownRemaining = remaining
            }
        }
    }

    // MARK: - Actions

    private func setStatus(_ status: UserStatus) {
        guard let uid = authManager.currentUser?.uid,
              let connectionId else { return }
        guard canSend else {
            FondHaptics.error()
            startCooldownTimer()
            return
        }

        withAnimation(.fondQuick) {
            myStatus = status
        }
        FondHaptics.statusChanged()
        lastSendTime = Date()
        errorMessage = nil

        Task {
            do {
                try await FirebaseManager.shared
                    .updateStatus(
                        uid: uid,
                        connectionId: connectionId,
                        status: status
                    )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty,
              let uid = authManager.currentUser?.uid,
              let connectionId else { return }
        guard canSend else {
            FondHaptics.error()
            startCooldownTimer()
            return
        }

        isSending = true
        lastSendTime = Date()
        errorMessage = nil
        let toSend = String(
            text.prefix(FondConstants.maxMessageLength)
        )
        messageText = ""

        Task {
            do {
                try await FirebaseManager.shared
                    .sendMessage(
                        uid: uid,
                        connectionId: connectionId,
                        message: toSend
                    )
                FondHaptics.messageSent()

                withAnimation(.fondQuick) {
                    sendSuccess = true
                    lastSentMessage = toSend
                    lastSentMessageTime = Date()
                }
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.fondQuick) {
                    sendSuccess = false
                }
            } catch {
                errorMessage = error.localizedDescription
                messageText = toSend
            }
            isSending = false
        }
    }

    private func sendNudge() {
        let now = Date()
        guard now.timeIntervalSince(lastNudgeTime) >= Double(FondConstants.nudgeCooldownSeconds) else {
            FondHaptics.error()
            withAnimation(.fondQuick) { nudgeShakeOffset = 4 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.fondQuick) { nudgeShakeOffset = -4 }
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.fondQuick) { nudgeShakeOffset = 4 }
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.fondQuick) { nudgeShakeOffset = 0 }
            }
            return
        }

        guard let uid = authManager.currentUser?.uid,
              let connectionId else { return }

        lastNudgeTime = now
        FondHaptics.messageSent()
        nudgeHintVisible = false

        withAnimation(.fondQuick) { nudgeScale = 1.02 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.fondQuick) { nudgeScale = 1.0 }
        }

        Task {
            do {
                try await FirebaseManager.shared.sendNudge(uid: uid, connectionId: connectionId)
            } catch {
                logger.error("Nudge failed: \(error.localizedDescription)")
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}
