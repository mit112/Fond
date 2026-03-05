//
//  DisplayNameView.swift
//  Fond
//
//  Shown after sign-in. The display name is what the partner sees on widgets.
//  Mesh gradient background, glass-styled input and button.
//
//  Design reference: docs/02-design-direction.md
//

import SwiftUI
import FirebaseAuth

struct DisplayNameView: View {
    var authManager: AuthManager
    var onComplete: () -> Void

    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        trimmedName.count >= 1 && trimmedName.count <= 30
    }

    var body: some View {
        ZStack {
            FondMeshGradient()

            VStack(spacing: 0) {
                Spacer()

                // Prompt
                VStack(spacing: 10) {
                    Text("What should your person call you?")
                        .font(.title2.bold())
                        .foregroundStyle(FondColors.text)
                        .multilineTextAlignment(.center)

                    Text("This is what your partner will see on their widgets.")
                        .font(.subheadline)
                        .foregroundStyle(FondColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()
                    .frame(height: 40)

                // Name input
                TextField("Your name", text: $name)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(FondColors.surface.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(FondColors.textSecondary.opacity(0.15), lineWidth: 1)
                    )
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit { save() }
                    .padding(.horizontal, 48)

                // Character count
                Text("\(trimmedName.count)/30")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(FondColors.textSecondary)
                    .contentTransition(.numericText())
                    .padding(.top, 8)

                Spacer()
                    .frame(height: 32)

                // Continue button
                Button {
                    save()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Continue")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .disabled(!isValid || isSaving)
                .fondGlassInteractive(
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                    tinted: true
                )
                .opacity(isValid ? 1.0 : 0.5)
                .padding(.horizontal, 36)
                .animation(.fondQuick, value: isValid)

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(FondColors.rose)
                        .padding(.top, 12)
                }

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            // Pre-fill with existing display name if available
            if let existing = authManager.currentUser?.displayName, !existing.isEmpty {
                name = existing
            }
            isFocused = true
        }
    }

    private func save() {
        guard isValid else { return }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await authManager.updateDisplayName(trimmedName)
                FondHaptics.pairingSuccess()
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
