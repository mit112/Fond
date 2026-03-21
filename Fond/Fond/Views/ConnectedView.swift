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

    // MARK: - Animation

    @State var partnerDataVisible = false
    @State private var isBreathing = false

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

                ConnectedPartnerCard(
                    partnerName: partnerName,
                    partnerStatus: partnerStatus,
                    partnerMessage: partnerMessage,
                    partnerLastUpdated: partnerLastUpdated,
                    partnerHeartbeatBpm: partnerHeartbeatBpm,
                    partnerHeartbeatTime: partnerHeartbeatTime,
                    distanceMiles: distanceMiles,
                    partnerCity: partnerCity,
                    isBreathing: isBreathing
                )
                .padding(.horizontal, 24)
                .opacity(partnerDataVisible ? 1 : 0)
                .scaleEffect(
                    partnerDataVisible ? 1 : 0.95
                )
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 4.0)
                            .repeatForever(autoreverses: true)
                    ) {
                        isBreathing = true
                    }
                }

                Spacer(minLength: 20)

                dailyPrompt

                statusIndicator
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                ConnectedMessageInput(
                    messageText: $messageText,
                    isSending: isSending,
                    sendSuccess: sendSuccess,
                    cooldownRemaining: cooldownRemaining,
                    errorMessage: errorMessage,
                    lastSentMessage: lastSentMessage,
                    onSend: sendMessage
                )
            }
        }
        .sheet(isPresented: $showStatusPicker) {
            StatusPickerSheet(
                currentStatus: myStatus
            ) { newStatus in
                setStatus(newStatus)
            }
        }
        .sheet(isPresented: $showHistory) {
            if let connectionId,
               let uid = authManager.currentUser?.uid {
                HistoryView(
                    connectionId: connectionId,
                    myUid: uid
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                authManager: authManager,
                connectionId: connectionId,
                onDisconnect: onDisconnect
            )
        }
        .task { await setupConnection() }
        .onChange(of: scenePhase) { _, newPhase in
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

            Text("Fond")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FondColors.textSecondary)

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

    // MARK: - Daily Prompt

    @ViewBuilder
    private var dailyPrompt: some View {
        if let uid = authManager.currentUser?.uid,
           let cid = connectionId {
            DailyPromptCard(
                partnerName: partnerName,
                uid: uid,
                connectionId: cid
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        Button {
            showStatusPicker = true
        } label: {
            HStack(spacing: 12) {
                Text(myStatus.emoji)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Status")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FondColors.textSecondary)
                        .tracking(0.3)
                    Text(myStatus.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FondColors.text)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        FondColors.textSecondary
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fondGlassInteractive(
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}
