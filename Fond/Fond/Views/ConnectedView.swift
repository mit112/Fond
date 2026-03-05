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

    @State private var partnerName: String = "..."
    @State private var partnerStatus: UserStatus?
    @State private var partnerMessage: String?
    @State private var partnerLastUpdated: Date?

    // MARK: - My State

    @State private var myStatus: UserStatus = .available
    @State private var messageText = ""
    @State private var isSending = false
    @State private var sendSuccess = false
    @State private var errorMessage: String?

    // MARK: - Rate Limiting

    @State private var lastSendTime: Date = .distantPast
    @State private var cooldownRemaining: Int = 0
    @State private var cooldownTimer: Timer?

    // MARK: - Connection Info

    @State private var connectionId: String?
    @State private var partnerUid: String?
    @State private var listener: ListenerRegistration?
    @State private var connectionListener: ListenerRegistration?

    // MARK: - Sheets

    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showStatusPicker = false

    // MARK: - Heartbeat

    @State private var partnerHeartbeatBpm: Int?
    @State private var partnerHeartbeatTime: Date?

    // MARK: - Distance

    @State private var distanceMiles: Double?
    @State private var partnerCity: String?
    @State private var myCity: String?

    // MARK: - Environment

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Animation

    @State private var partnerDataVisible = false
    @State private var emojiBounce = false
    @State private var isBreathing = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Layer 0: Animated mesh gradient background
            FondMeshGradient()

            // Layer 1: Content
            VStack(spacing: 0) {
                // Floating toolbar
                toolbar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer()

                // Partner card — the hero element
                partnerCard
                    .padding(.horizontal, 24)
                    .opacity(partnerDataVisible ? 1 : 0)
                    .scaleEffect(partnerDataVisible ? 1 : 0.95)

                // Distance pill — shown when both locations available
                if let miles = distanceMiles {
                    distancePill(miles: miles)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .scale))
                }

                Spacer()

                // Daily prompt card
                if let uid = authManager.currentUser?.uid, let cid = connectionId {
                    DailyPromptCard(
                        partnerName: partnerName,
                        uid: uid,
                        connectionId: cid
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }

                // Status indicator — tap to open picker
                statusIndicator
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                // Message input
                messageInput
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                // Cooldown / error / char count feedback
                feedbackBar
                    .padding(.bottom, 8)
                    .animation(.fondQuick, value: errorMessage)
                    .animation(.fondQuick, value: charCount)
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
        .task { await setup() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Re-capture location on every foreground return
                #if canImport(CoreLocation)
                if let uid = authManager.currentUser?.uid {
                    Task {
                        await LocationManager.shared.captureAndUpload(uid: uid)
                    }
                }
                #endif
                // Refresh today's prompt (may have changed overnight)
                DailyPromptManager.shared.computeTodaysPrompt()
            }
        }
        .onDisappear {
            listener?.remove()
            connectionListener?.remove()
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

    // MARK: - Partner Card

    private var partnerCard: some View {
        VStack(spacing: 16) {
            // Status emoji — the visual anchor
            Text(partnerStatus?.emoji ?? "⏳")
                .font(.system(size: 80))
                .scaleEffect(emojiBounce ? 1.2 : 1.0)
                .animation(.fondSpring, value: emojiBounce)

            // Partner name — largest text on screen
            Text(partnerName)
                .font(.largeTitle.bold())
                .foregroundStyle(FondColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Status label
            if let status = partnerStatus {
                Text(status.displayName)
                    .font(.title3)
                    .foregroundStyle(status.statusColor)
            }

            // Partner message
            if let message = partnerMessage, !message.isEmpty {
                Text(message)
                    .font(.body)
                    .foregroundStyle(FondColors.text.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            }

            // Time ago
            if let lastUpdated = partnerLastUpdated {
                Text(lastUpdated.shortTimeAgo)
                    .font(.caption)
                    .foregroundStyle(FondColors.textSecondary)
                    .contentTransition(.numericText())
            }

            // Heartbeat pill — shown when a recent heartbeat exists (< 30 min)
            if let bpm = partnerHeartbeatBpm,
               let time = partnerHeartbeatTime,
               Date().timeIntervalSince(time) < 1800 {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(FondColors.rose)
                        .symbolEffect(.pulse, options: .repeating)
                    Text("\(bpm) bpm")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(FondColors.text)
                    Text("• \(time.shortTimeAgo)")
                        .font(.caption2)
                        .foregroundStyle(FondColors.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(FondColors.rose.opacity(0.1))
                )
                .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .fondCard()
        .scaleEffect(isBreathing ? 1.003 : 1.0)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 4.0)
                .repeatForever(autoreverses: true)
            ) {
                isBreathing = true
            }
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
                    Text("YOUR STATUS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FondColors.textSecondary)
                        .tracking(1.0)
                    Text(myStatus.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FondColors.text)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FondColors.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .fondGlassInteractive(
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    // MARK: - Message Input

    private var messageInput: some View {
        HStack(spacing: 10) {
            TextField("Send a message...", text: $messageText)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(FondColors.surface.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(FondColors.textSecondary.opacity(0.15), lineWidth: 1)
                )
                .submitLabel(.send)
                .onSubmit { sendMessage() }

            sendButton
        }
    }

    /// Cooldown progress for the ring overlay (1.0 = full cooldown, 0.0 = ready).
    private var cooldownProgress: CGFloat {
        guard cooldownRemaining > 0 else { return 0 }
        return CGFloat(cooldownRemaining) / CGFloat(FondConstants.rateLimitSeconds)
    }

    private var sendButton: some View {
        Button {
            sendMessage()
        } label: {
            Group {
                if isSending {
                    ProgressView()
                        .tint(FondColors.text)
                } else if sendSuccess {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 42, height: 42)
            .contentTransition(.symbolEffect(.replace))
        }
        .disabled(
            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || isSending
        )
        .fondGlassInteractive(in: Circle(), tinted: true)
        .overlay {
            // Circular cooldown ring — depletes as cooldown expires
            if cooldownProgress > 0 {
                Circle()
                    .trim(from: 0, to: cooldownProgress)
                    .stroke(
                        FondColors.amber.opacity(0.5),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 46, height: 46)
                    .animation(.linear(duration: 1), value: cooldownProgress)
            }
        }
    }

    // MARK: - Feedback Bar

    /// Character count hint — visible when approaching limit.
    private var charCount: Int {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    @ViewBuilder
    private var feedbackBar: some View {
        if let error = errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(FondColors.rose)
                .transition(.opacity)
        } else if charCount > Int(Double(FondConstants.maxMessageLength) * 0.7) {
            Text("\(charCount)/\(FondConstants.maxMessageLength)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    charCount >= FondConstants.maxMessageLength
                        ? FondColors.rose
                        : FondColors.textSecondary
                )
                .contentTransition(.numericText())
                .transition(.opacity)
        } else {
            Color.clear.frame(height: 16)
        }
    }

    // MARK: - Distance Pill

    private func distancePill(miles: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill")
                .font(.caption2)
                .foregroundStyle(FondColors.amber)
            Text(LocationManager.formattedDistance(miles))
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(FondColors.text)
            if let city = partnerCity {
                Text("• \(city)")
                    .font(.caption2)
                    .foregroundStyle(FondColors.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(FondColors.amber.opacity(0.1))
        )
    }

    // MARK: - Setup & Listener

    private func setup() async {
        guard let uid = authManager.currentUser?.uid else { return }

        do {
            let data = try await FirebaseManager.shared.fetchUserData(uid: uid)
            connectionId = data.connectionId
            partnerUid = data.partnerUid

            // Cache connection info so watch actions can route to Firestore
            if let cid = data.connectionId {
                WatchSyncManager.shared.setConnectionInfo(uid: uid, connectionId: cid)
            }

            if let partnerUid = data.partnerUid {
                startListening(partnerUid: partnerUid)
            }

            // Listen for connection doc changes (e.g., partner sets anniversary)
            if let cid = data.connectionId {
                startConnectionListener(connectionId: cid)
            }

            // Capture + upload location on appear
            #if canImport(CoreLocation)
            await LocationManager.shared.captureAndUpload(uid: uid)
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startListening(partnerUid: String) {
        listener = FirebaseManager.shared.listenToPartner(partnerUid: partnerUid) { update in

            // Decrypt on receive
            let name = EncryptionManager.shared.decryptOrNil(update.encryptedName) ?? "Your person"
            var status: UserStatus?
            if let encStatus = update.encryptedStatus,
               let statusRaw = EncryptionManager.shared.decryptOrNil(encStatus) {
                status = UserStatus(rawValue: statusRaw)
            }
            let message = EncryptionManager.shared.decryptOrNil(update.encryptedMessage)

            // Parse heartbeat if present
            var heartbeatBpm: Int?
            if let encHB = update.encryptedHeartbeat,
               let json = EncryptionManager.shared.decryptOrNil(encHB),
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let bpm = dict["bpm"] as? Int {
                heartbeatBpm = bpm
            }

            // Capture old values before updating (for change detection)
            let wasVisible = partnerDataVisible
            let oldStatus = self.partnerStatus
            let oldMessage = self.partnerMessage
            let oldBpm = self.partnerHeartbeatBpm

            // Animate partner data in
            withAnimation(.fondSpring) {
                self.partnerName = name
                self.partnerStatus = status
                self.partnerMessage = message
                self.partnerLastUpdated = update.lastUpdated

                if let bpm = heartbeatBpm {
                    self.partnerHeartbeatBpm = bpm
                    self.partnerHeartbeatTime = Date()
                }

                if !partnerDataVisible {
                    partnerDataVisible = true
                }
            }

            // Emoji bounce on status change (skip initial load)
            if wasVisible && status != oldStatus {
                emojiBounce = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    emojiBounce = false
                }
            }

            // Haptic on partner update (skip initial load)
            if wasVisible && (status != oldStatus || message != oldMessage) {
                FondHaptics.partnerUpdated()
            }

            // Extra haptic for new heartbeat
            if wasVisible && heartbeatBpm != nil && heartbeatBpm != oldBpm {
                FondHaptics.partnerUpdated()
            }

            // Handle partner's prompt answer
            DailyPromptManager.shared.receivePartnerAnswer(
                encryptedAnswer: update.encryptedPromptAnswer
            )

            // Compute distance from partner's encrypted location
            var computedDistance: Double?
            var computedCity: String?
            #if canImport(CoreLocation)
            if let encLoc = update.encryptedLocation,
               let locJSON = EncryptionManager.shared.decryptOrNil(encLoc),
               let locData = locJSON.data(using: .utf8),
               let locDict = try? JSONSerialization.jsonObject(with: locData) as? [String: Any],
               let partnerLat = locDict["lat"] as? Double,
               let partnerLon = locDict["lon"] as? Double,
               let myLat = LocationManager.shared.latitude,
               let myLon = LocationManager.shared.longitude {
                let miles = LocationManager.haversineDistance(
                    lat1: myLat, lon1: myLon,
                    lat2: partnerLat, lon2: partnerLon
                )
                computedDistance = miles
                withAnimation(.fondQuick) {
                    self.distanceMiles = miles
                }

                // Reverse geocode partner city (async, non-blocking)
                Task {
                    if let city = await LocationManager.reverseGeocode(lat: partnerLat, lon: partnerLon) {
                        self.partnerCity = city
                        computedCity = city
                    }
                }
            }
            #endif

            // Write to App Group so widgets can read
            FirebaseManager.shared.writePartnerDataToAppGroup(
                name: name,
                status: status,
                message: message,
                lastUpdated: update.lastUpdated,
                heartbeatBpm: heartbeatBpm,
                distanceMiles: computedDistance,
                partnerCity: computedCity
            )

            // Sync to Apple Watch
            WatchSyncManager.shared.syncPartnerData(
                name: name,
                status: status?.rawValue,
                statusEmoji: status?.emoji,
                message: message,
                lastUpdated: update.lastUpdated,
                heartbeatBpm: heartbeatBpm,
                distanceMiles: computedDistance,
                promptText: DailyPromptManager.shared.todaysPrompt?.text,
                partnerPromptAnswer: DailyPromptManager.shared.partnerAnswer
            )

            // Trigger widget refresh
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Connection Listener

    private func startConnectionListener(connectionId: String) {
        connectionListener = FirebaseManager.shared.listenToConnection(
            connectionId: connectionId
        ) { anniversaryDate in
            // Write to App Group so widgets can compute day count
            guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else { return }
            if let date = anniversaryDate {
                defaults.set(date, forKey: FondConstants.anniversaryDateKey)
            } else {
                defaults.removeObject(forKey: FondConstants.anniversaryDateKey)
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Rate Limiting

    private var canSend: Bool {
        Date().timeIntervalSince(lastSendTime) >= Double(FondConstants.rateLimitSeconds)
    }

    private func startCooldownTimer() {
        let elapsed = Int(Date().timeIntervalSince(lastSendTime))
        cooldownRemaining = max(FondConstants.rateLimitSeconds - elapsed, 0)
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let elapsed = Int(Date().timeIntervalSince(lastSendTime))
            let remaining = FondConstants.rateLimitSeconds - elapsed
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
                try await FirebaseManager.shared.updateStatus(
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
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let messageToSend = String(text.prefix(FondConstants.maxMessageLength))
        messageText = ""

        Task {
            do {
                try await FirebaseManager.shared.sendMessage(
                    uid: uid,
                    connectionId: connectionId,
                    message: messageToSend
                )
                FondHaptics.messageSent()

                // Flash checkmark
                withAnimation(.fondQuick) { sendSuccess = true }
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.fondQuick) { sendSuccess = false }
            } catch {
                errorMessage = error.localizedDescription
                messageText = messageToSend // Restore on failure
            }
            isSending = false
        }
    }
}
