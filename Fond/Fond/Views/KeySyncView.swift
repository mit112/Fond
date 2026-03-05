//
//  KeySyncView.swift
//  Fond
//
//  Shown when a user logs into an existing connected account on a new device
//  but the encryption keys haven't synced via iCloud Keychain yet.
//
//  Periodically retries key derivation:
//  1. Checks if the symmetric key has synced directly (fastest path)
//  2. If not, checks if the private key synced → re-derives symmetric key from partner's public key
//  3. Polls every 3 seconds until keys are available
//
//  On real devices, iCloud Keychain typically syncs within seconds to minutes.
//  In simulator, iCloud Keychain doesn't work — shows a manual re-pair option after timeout.
//
//  Design: Warm mesh gradient, breathing heart, clear status messaging.
//

import SwiftUI

struct KeySyncView: View {
    let partnerUid: String
    let onKeysReady: () -> Void

    @State private var retryCount = 0
    @State private var isRetrying = false
    @State private var showManualOption = false
    @State private var timer: Timer?

    /// Show the re-pair option after this many retries (~30 seconds)
    private let maxAutoRetries = 10

    var body: some View {
        ZStack {
            FondMeshGradient()

            VStack(spacing: 24) {
                Spacer()

                // Breathing lock icon
                Image(systemName: "lock.icloud")
                    .font(.system(size: 52))
                    .foregroundStyle(FondColors.amber)
                    .symbolEffect(.breathe)

                VStack(spacing: 8) {
                    Text("Syncing Encryption Keys")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(FondColors.text)

                    Text("Waiting for your encryption keys to sync from your other device via iCloud Keychain.")
                        .font(.subheadline)
                        .foregroundStyle(FondColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if isRetrying {
                    ProgressView()
                        .tint(FondColors.amber)
                        .padding(.top, 8)
                }

                Spacer()

                // Status footer
                VStack(spacing: 16) {
                    if showManualOption {
                        VStack(spacing: 12) {
                            Text("Keys haven't arrived yet. This can happen on simulators or if iCloud Keychain is disabled.")
                                .font(.caption)
                                .foregroundStyle(FondColors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            Button {
                                retryNow()
                            } label: {
                                Text("Retry Now")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(FondColors.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .fondGlassInteractive(
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                tinted: true
                            )
                            .padding(.horizontal, 40)
                        }
                    } else {
                        Text("Attempt \(retryCount)…")
                            .font(.caption)
                            .foregroundStyle(FondColors.textSecondary)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Polling

    private func startPolling() {
        // Try immediately on appear
        tryResolveKeys()

        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            tryResolveKeys()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func retryNow() {
        retryCount = 0
        showManualOption = false
        tryResolveKeys()
    }

    private func tryResolveKeys() {
        isRetrying = true
        retryCount += 1

        // Path 1: Symmetric key already synced directly via iCloud Keychain
        if KeyExchangeManager.shared.hasSymmetricKey {
            stopPolling()
            FondHaptics.pairingSuccess()
            onKeysReady()
            return
        }

        // Path 2: Private key synced → re-derive symmetric key from partner's public key
        if KeyExchangeManager.shared.hasPrivateKey {
            Task {
                do {
                    let success = try await FirebaseManager.shared.completeKeyExchange(
                        partnerUid: partnerUid
                    )
                    if success {
                        stopPolling()
                        FondHaptics.pairingSuccess()
                        onKeysReady()
                        return
                    }
                } catch {
                    // Private key exists but derivation failed — keep trying
                }
                isRetrying = false
            }
            return
        }

        // Neither key has synced yet
        isRetrying = false

        if retryCount >= maxAutoRetries && !showManualOption {
            withAnimation(.fondSpring) {
                showManualOption = true
            }
        }
    }
}
