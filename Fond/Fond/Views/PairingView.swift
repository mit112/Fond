//
//  PairingView.swift
//  Fond
//
//  Two-tab view: Generate a code OR enter a partner's code.
//  Glass segmented control, large code display, character-slot entry.
//
//  Design reference: docs/02-design-direction.md
//

import SwiftUI
import FirebaseAuth

struct PairingView: View {
    var authManager: AuthManager
    var onConnected: () -> Void

    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            FondMeshGradient()

            VStack(spacing: 28) {
                Spacer()
                    .frame(height: 20)

                Text("Connect with your person")
                    .font(.title2.bold())
                    .foregroundStyle(FondColors.text)

                // Glass segmented picker
                HStack(spacing: 0) {
                    segmentButton("Share Code", tag: 0)
                    segmentButton("Enter Code", tag: 1)
                }
                .padding(4)
                .fondGlassPlain(
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .padding(.horizontal, 36)

                if selectedTab == 0 {
                    GenerateCodeView(
                        authManager: authManager,
                        onConnected: onConnected
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    EnterCodeView(
                        authManager: authManager,
                        onConnected: onConnected
                    )
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                Spacer()
            }
            .animation(.fondSpring, value: selectedTab)
        }
    }

    @Namespace private var segmentNamespace

    private func segmentButton(_ title: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag
        return Button {
            selectedTab = tag
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(
                    isSelected ? FondColors.text : FondColors.textSecondary
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .fondGlass(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            tinted: isSelected
        )
        .opacity(isSelected ? 1.0 : 0.6)
        .animation(.fondQuick, value: selectedTab)
    }
}

// MARK: - Generate Code Tab

struct GenerateCodeView: View {
    var authManager: AuthManager
    var onConnected: () -> Void

    @State private var code: String?
    @State private var isGenerating = false
    @State private var isPolling = false
    @State private var errorMessage: String?
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            Text("Share this code with your partner")
                .font(.subheadline)
                .foregroundStyle(FondColors.textSecondary)

            if let code {
                // Code display card
                VStack(spacing: 12) {
                    Text(code)
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(FondColors.text)
                        .tracking(8)

                    Text("Expires in 10 minutes")
                        .font(.caption)
                        .foregroundStyle(FondColors.textSecondary)
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 32)
                .fondCard()

                if isPolling {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for your partner...")
                            .font(.subheadline)
                            .foregroundStyle(FondColors.textSecondary)
                    }
                    .padding(.top, 4)
                }

                Button {
                    UIPasteboard.general.string = code
                    FondHaptics.statusChanged()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.subheadline)
                        Text("Copy Code")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(FondColors.text)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .fondGlassInteractive(
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .padding(.top, 4)
            } else {
                Button {
                    generateCode()
                } label: {
                    Group {
                        if isGenerating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Generate Code")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .disabled(isGenerating)
                .fondGlassInteractive(
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                    tinted: true
                )
                .padding(.horizontal, 36)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(FondColors.rose)
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
        }
    }

    private func generateCode() {
        guard let uid = authManager.currentUser?.uid else { return }
        isGenerating = true
        errorMessage = nil

        Task {
            do {
                try await FirebaseManager.shared.publishPublicKey(uid: uid)
                let newCode = try await FirebaseManager.shared.generatePairingCode(creatorUid: uid)
                withAnimation(.fondSpring) {
                    code = newCode
                }
                isGenerating = false
                startPolling(uid: uid)
            } catch {
                errorMessage = error.localizedDescription
                isGenerating = false
            }
        }
    }

    private func startPolling(uid: String) {
        isPolling = true
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                if let partnerUid = try? await FirebaseManager.shared.checkConnection(uid: uid) {
                    let _ = try? await FirebaseManager.shared.completeKeyExchange(partnerUid: partnerUid)
                    pollTimer?.invalidate()
                    isPolling = false
                    FondHaptics.pairingSuccess()
                    onConnected()
                }
            }
        }
    }
}

// MARK: - Enter Code Tab

struct EnterCodeView: View {
    var authManager: AuthManager
    var onConnected: () -> Void

    @State private var code = ""
    @State private var isLinking = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private let codeLength = FondConstants.codeLength

    private var isValid: Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).count == codeLength
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter your partner's code")
                .font(.subheadline)
                .foregroundStyle(FondColors.textSecondary)

            // Character slots
            HStack(spacing: 10) {
                ForEach(0..<codeLength, id: \.self) { index in
                    characterSlot(at: index)
                }
            }
            .padding(.horizontal, 24)

            // Hidden text field drives the input
            TextField("", text: $code)
                .focused($isFocused)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .opacity(0)
                .frame(height: 1)
                .onChange(of: code) { _, newValue in
                    // Limit to code length
                    let filtered = String(
                        newValue.uppercased()
                            .filter { $0.isLetter || $0.isNumber }
                            .prefix(codeLength)
                    )
                    if filtered != code {
                        code = filtered
                    }
                    // Auto-submit when complete
                    if filtered.count == codeLength && !isLinking {
                        link()
                    }
                }

            if isLinking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting...")
                        .font(.subheadline)
                        .foregroundStyle(FondColors.textSecondary)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(FondColors.rose)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
        .onAppear {
            isFocused = true
        }
        .onTapGesture {
            isFocused = true
        }
    }

    /// Individual character slot with scale-up animation when filled.
    private func characterSlot(at index: Int) -> some View {
        let characters = Array(code)
        let isFilled = index < characters.count
        let character = isFilled ? String(characters[index]) : ""

        return Text(character)
            .font(.system(size: 28, weight: .bold, design: .monospaced))
            .foregroundStyle(FondColors.text)
            .frame(width: 44, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FondColors.surface.opacity(isFilled ? 0.7 : 0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isFilled ? FondColors.amber.opacity(0.5) : FondColors.textSecondary.opacity(0.15),
                        lineWidth: isFilled ? 1.5 : 1
                    )
            )
            .scaleEffect(isFilled ? 1.0 : 0.92)
            .animation(.fondQuick, value: isFilled)
    }

    private func link() {
        guard isValid, let uid = authManager.currentUser?.uid else { return }
        isLinking = true
        errorMessage = nil

        Task {
            do {
                try await FirebaseManager.shared.publishPublicKey(uid: uid)
                try await FirebaseManager.shared.linkUsers(code: code, claimerUid: uid)
                if let partnerUid = try await FirebaseManager.shared.checkConnection(uid: uid) {
                    let _ = try await FirebaseManager.shared.completeKeyExchange(partnerUid: partnerUid)
                }
                FondHaptics.pairingSuccess()
                onConnected()
            } catch {
                errorMessage = error.localizedDescription
                // Reset code on failure so user can retry
                withAnimation(.fondQuick) { code = "" }
                FondHaptics.error()
            }
            isLinking = false
        }
    }
}
