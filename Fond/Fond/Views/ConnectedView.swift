import SwiftUI
import WidgetKit
import FirebaseAuth
import FirebaseFirestore
import os

private let logger = Logger(subsystem: "com.mitsheth.Fond", category: "ConnectedView")

struct ConnectedView: View {
    var authManager: AuthManager
    var onDisconnect: () -> Void

    @State var partnerName = "..."
    @State var partnerStatus: UserStatus?
    @State var partnerMessage: String?
    @State var partnerLastUpdated: Date?

    @State private var myStatus: UserStatus = .available
    @State private var messageText = ""
    @State private var isSending = false
    @State private var sendSuccess = false
    @State var errorMessage: String?

    @State private var lastSendTime = Date.distantPast
    @State private var cooldownRemaining = 0
    @State private var cooldownTimer: Timer?

    @State var connectionId: String?
    @State var partnerUid: String?
    @State var listener: ListenerRegistration?
    @State var connectionListener: ListenerRegistration?

    @State private var showSettings = false
    @State private var showStatusPicker = false

    @State var partnerHeartbeatBpm: Int?
    @State var partnerHeartbeatTime: Date?
    @State var lastLocationCapture = Date.distantPast
    @State var distanceMiles: Double?
    @State var partnerCity: String?

    @State var partnerDataVisible = false
    @State var lastNudgeReceivedTime: Date?

    @State private var activeFace: FondFace = .now
    @State private var isCardDragging = false
    @State private var isBreathing = false
    @State private var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var nudgeEdgePulse = false
    @State private var nudgeResistance: CGFloat = 0
    @State private var lastNudgeTime = Date.distantPast
    @State private var threadStore: TogetherThreadStore?
    @State private var promptManager = DailyPromptManager.shared
    @State var relationshipLine: String?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            FondField()
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }

            VStack(spacing: FondSpacing.three) {
                toolbar

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    CardTurnContainer(
                        face: $activeFace,
                        isDragging: $isCardDragging,
                        reduceMotion: reduceMotion
                    ) {
                        NowFaceView(
                            model: nowFaceModel(now: context.date),
                            isBreathing: isBreathing,
                            onNudge: sendNudge
                        )
                        .fondKeepsakeCard()
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: FondGeometry.cardCornerRadius,
                                style: .continuous
                            )
                            .stroke(FondColors.amber, lineWidth: 3)
                            .opacity(nudgeEdgePulse ? 1 : 0)
                            .accessibilityHidden(true)
                        }
                        .offset(x: nudgeResistance)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("fond.face.now")
                    } back: {
                        TogetherFaceView(
                            state: todayRitualState,
                            moments: threadStore?.moments ?? [],
                            hasMore: threadStore?.hasMore ?? false,
                            onAnswer: submitPromptAnswer,
                            onLoadMore: loadMoreMoments
                        )
                        .fondKeepsakeCard()
                        .scaleEffect(isBreathing ? 1.003 : 1)
                        .animation(breathingAnimation, value: isBreathing)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("fond.face.together")
                    }
                    .frame(maxWidth: contentMaxWidth, maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("fond.card")
                }
                .frame(maxHeight: .infinity)

                PageDotsView(count: 2, activeIndex: activeFace.rawValue)
                    .accessibilityLabel(activeFace == .now ? "Now face" : "Together face")

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
                .frame(maxWidth: contentMaxWidth)
            }
            .padding(.horizontal, cardMargin)
            .padding(.top, FondSpacing.two)
            .padding(.bottom, FondSpacing.three)
        }
        .sheet(isPresented: $showStatusPicker) {
            StatusPickerSheet(currentStatus: myStatus) { newStatus in
                setStatus(newStatus)
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: refreshRelationshipLine) {
            SettingsView(
                authManager: authManager,
                connectionId: connectionId,
                onDisconnect: onDisconnect
            )
        }
        .task { await setupConnection() }
        .onAppear {
            refreshRelationshipLine()
            restartBreathing()
        }
        .onChange(of: isCardDragging) { _, _ in restartBreathing() }
        .onChange(of: reduceMotion) { _, _ in restartBreathing() }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
            if newPhase == .active {
                refreshRelationshipLine()
                isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                restartBreathing()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSProcessInfoPowerStateDidChange
            )
        ) { _ in
            isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            restartBreathing()
        }
        .onDisappear {
            listener?.remove()
            connectionListener?.remove()
            cooldownTimer?.invalidate()
            cooldownTimer = nil
        }
    }

    private var toolbar: some View {
        HStack(spacing: FondSpacing.two) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .foregroundStyle(FondColors.ink)
                    .frame(width: FondGeometry.minimumTarget, height: FondGeometry.minimumTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")

            Spacer(minLength: FondSpacing.one)

            facePicker

            Spacer(minLength: FondSpacing.one)

            Button {
                activeFace = .together
            } label: {
                Image(systemName: "text.justify.leading")
                    .font(.body.weight(.medium))
                    .foregroundStyle(FondColors.ink)
                    .frame(width: FondGeometry.minimumTarget, height: FondGeometry.minimumTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show Together thread")
        }
        .frame(height: FondGeometry.controlHeight)
        .padding(.horizontal, FondSpacing.one)
        .fondFloatingControl(in: Capsule())
        .frame(maxWidth: contentMaxWidth)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fond.toolbar")
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var facePicker: some View {
        HStack(spacing: FondSpacing.two) {
            faceButton("Now", face: .now)
                .keyboardShortcut("1", modifiers: .command)

            Text("·")
                .font(FondType.control)
                .foregroundStyle(FondColors.amber)
                .accessibilityHidden(true)

            faceButton("Together", face: .together)
                .keyboardShortcut("2", modifiers: .command)
        }
        .padding(.horizontal, FondSpacing.four)
        .frame(height: 36)
        .fondControlPlate(in: Capsule())
    }

    private func faceButton(_ label: String, face: FondFace) -> some View {
        let isActive = activeFace == face
        return Button {
            activeFace = face
        } label: {
            Text(label)
                .font(FondType.control)
                .foregroundStyle(
                    isActive || colorSchemeContrast == .increased
                        ? FondColors.ink
                        : FondColors.inkSecondary
                )
                .frame(minHeight: FondGeometry.minimumTarget)
                .overlay(alignment: .bottom) {
                    if isActive && differentiateWithoutColor {
                        Capsule()
                            .fill(FondColors.amber)
                            .frame(width: 12, height: 2)
                            .offset(y: -6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var cardMargin: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 40
        #else
        horizontalSizeClass == .regular
            ? FondGeometry.cardMarginRegular
            : FondGeometry.cardMarginCompact
        #endif
    }

    private var contentMaxWidth: CGFloat {
        #if targetEnvironment(macCatalyst)
        680
        #else
        FondGeometry.contentMaxWidth
        #endif
    }

    private var isDataStale: Bool {
        guard let partnerLastUpdated else { return false }
        return Date().timeIntervalSince(partnerLastUpdated) > 3_600
    }

    private func nowFaceModel(now: Date) -> NowFaceModel {
        let heartbeatIsFresh = partnerHeartbeatTime.map {
            now.timeIntervalSince($0) < 1_800
        } ?? false
        return NowFaceModel(
            partnerName: partnerName,
            status: partnerStatus,
            message: partnerMessage == "💛" ? nil : partnerMessage,
            lastUpdated: partnerLastUpdated,
            heartbeatBpm: heartbeatIsFresh ? partnerHeartbeatBpm : nil,
            heartbeatTime: heartbeatIsFresh ? partnerHeartbeatTime : nil,
            distanceMiles: distanceMiles,
            relationshipLine: relationshipLine,
            isStale: isDataStale
        )
    }

    private var todayRitualState: TodayRitualState {
        let phase: TodayRitualState.Phase
        if let myAnswer = promptManager.myAnswer {
            if let partnerAnswer = promptManager.partnerAnswer {
                phase = .revealed(myAnswer: myAnswer, partnerAnswer: partnerAnswer)
            } else {
                phase = .waiting(myAnswer: myAnswer)
            }
        } else {
            phase = .unanswered
        }
        return TodayRitualState(
            question: promptManager.todaysPrompt?.text ?? "What would you like to remember today?",
            partnerName: partnerName,
            phase: phase,
            isSubmitting: promptManager.isSubmitting,
            errorMessage: promptManager.lastError
        )
    }

    private var breathingAnimation: Animation? {
        isBreathing
            ? .easeInOut(duration: 5.6).repeatForever(autoreverses: true)
            : .easeOut(duration: 0.12)
    }

    private func restartBreathing() {
        isBreathing = false
        guard !reduceMotion, !isLowPowerMode, !isCardDragging else { return }
        Task { @MainActor in
            await Task.yield()
            guard !reduceMotion, !isLowPowerMode, !isCardDragging else { return }
            isBreathing = true
        }
    }

    func initializeThreadStore(uid: String, connectionId: String) async {
        let store = TogetherThreadStore(
            provider: FirebaseHistoryProvider(),
            myUid: uid,
            decrypt: EncryptionManager.shared.decryptOrNil,
            promptText: DailyPromptManager.shared.promptText
        )
        threadStore = store
        await store.loadInitial(connectionId: connectionId)
    }

    func refreshThread() async {
        guard let connectionId, let threadStore else { return }
        await threadStore.loadInitial(connectionId: connectionId)
    }

    func refreshRelationshipLine() {
        let defaults = UserDefaults(suiteName: FondConstants.appGroupID)
        relationshipLine = RelationshipDateSummary.make(
            anniversary: defaults?.object(forKey: FondConstants.anniversaryDateKey) as? Date,
            countdown: defaults?.object(forKey: FondConstants.countdownDateKey) as? Date,
            label: defaults?.string(forKey: FondConstants.countdownLabelKey)
        )
    }

    private func loadMoreMoments() {
        guard let connectionId, let threadStore else { return }
        Task { await threadStore.loadMore(connectionId: connectionId) }
    }

    private func submitPromptAnswer(_ answer: String) {
        guard let uid = authManager.currentUser?.uid, let connectionId else { return }
        Task {
            await promptManager.submitAnswer(
                answer: answer,
                uid: uid,
                connectionId: connectionId
            )
            if promptManager.lastError == nil { await refreshThread() }
        }
    }

    private var canSend: Bool {
        Date().timeIntervalSince(lastSendTime) >= Double(FondConstants.rateLimitSeconds)
    }

    private func startCooldownTimer() {
        let elapsed = Int(Date().timeIntervalSince(lastSendTime))
        cooldownRemaining = max(FondConstants.rateLimitSeconds - elapsed, 0)
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
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

    private func setStatus(_ status: UserStatus) {
        guard let uid = authManager.currentUser?.uid, let connectionId else { return }
        guard canSend else {
            FondHaptics.error()
            startCooldownTimer()
            return
        }
        withAnimation(.fondQuick) { myStatus = status }
        FondHaptics.statusChanged()
        lastSendTime = .now
        errorMessage = nil

        Task {
            do {
                try await FirebaseManager.shared.updateStatus(
                    uid: uid,
                    connectionId: connectionId,
                    status: status
                )
                await refreshThread()
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
        lastSendTime = .now
        errorMessage = nil
        let toSend = String(text.prefix(FondConstants.maxMessageLength))
        messageText = ""

        Task {
            do {
                try await FirebaseManager.shared.sendMessage(
                    uid: uid,
                    connectionId: connectionId,
                    message: toSend
                )
                FondHaptics.messageSent()
                withAnimation(.fondQuick) { sendSuccess = true }
                await refreshThread()
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.fondQuick) { sendSuccess = false }
            } catch {
                errorMessage = error.localizedDescription
                messageText = toSend
            }
            isSending = false
        }
    }

    private func sendNudge() {
        let now = Date.now
        guard now.timeIntervalSince(lastNudgeTime) >= Double(FondConstants.nudgeCooldownSeconds) else {
            FondHaptics.error()
            withAnimation(.interpolatingSpring(stiffness: 420, damping: 20)) {
                nudgeResistance = -6
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.interpolatingSpring(stiffness: 420, damping: 20)) {
                    nudgeResistance = 0
                }
            }
            return
        }
        guard let uid = authManager.currentUser?.uid, let connectionId else { return }

        lastNudgeTime = now
        FondHaptics.nudgeSent()
        withAnimation(.easeOut(duration: 0.12)) { nudgeEdgePulse = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            nudgeEdgePulse = false
        }

        Task {
            do {
                try await FirebaseManager.shared.sendNudge(uid: uid, connectionId: connectionId)
                await refreshThread()
            } catch {
                logger.error("Nudge failed: \(error.localizedDescription)")
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
