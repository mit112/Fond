//
//  ContentView.swift
//  Fond
//
//  Root view — routes through: Sign In → Display Name → Pairing → Connected.
//  Smooth cross-fade transitions between states. Warm loading screen.
//
//  Also handles the key sync edge case: when a user logs into an existing
//  connected account on a new device, encryption keys may not be available
//  yet (iCloud Keychain sync). Shows KeySyncView until keys arrive.
//
//  Design reference: docs/02-design-direction.md
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @State private var authManager = AuthManager.shared
    @State private var displayNameComplete = false
    @State private var isConnected = false
    @State private var isCheckingConnection = true

    // Key sync state — for existing accounts on new devices
    @State private var needsKeySync = false
    @State private var partnerUidForSync: String?

    var body: some View {
        Group {
            if authManager.isInitializing {
                loadingView
            } else if !authManager.isSignedIn {
                SignInView(authManager: authManager)
                    .transition(.opacity)
            } else if isCheckingConnection {
                loadingView
                    .transition(.opacity)
            } else if !displayNameComplete {
                DisplayNameView(authManager: authManager) {
                    displayNameComplete = true
                }
                .transition(.opacity)
            } else if needsKeySync, let partnerUid = partnerUidForSync {
                KeySyncView(partnerUid: partnerUid) {
                    needsKeySync = false
                    isConnected = true
                }
                .transition(.opacity)
            } else if !isConnected {
                PairingView(authManager: authManager) {
                    isConnected = true
                }
                .transition(.opacity)
            } else {
                ConnectedView(authManager: authManager) {
                    isConnected = false
                    needsKeySync = false
                    partnerUidForSync = nil
                }
                .transition(.opacity)
            }
        }
        .animation(.fondSpring, value: authManager.isSignedIn)
        .animation(.fondSpring, value: isConnected)
        .animation(.fondSpring, value: displayNameComplete)
        .animation(.fondSpring, value: isCheckingConnection)
        .animation(.fondSpring, value: needsKeySync)
        .onChange(of: authManager.isSignedIn) { _, signedIn in
            if signedIn {
                checkExistingConnection()
            } else {
                displayNameComplete = false
                isConnected = false
                isCheckingConnection = false
                needsKeySync = false
                partnerUidForSync = nil
            }
        }
        .task {
            if authManager.isSignedIn {
                checkExistingConnection()
            } else {
                isCheckingConnection = false
            }
        }
    }

    // MARK: - Loading View

    /// Warm loading screen — mesh gradient + breathing heart.
    /// Shown during Firebase init and connection check.
    private var loadingView: some View {
        ZStack {
            FondMeshGradient()

            VStack(spacing: 16) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(FondColors.amber)
                    .symbolEffect(.breathe)

                Text("Fond")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(FondColors.textSecondary)
            }
        }
    }

    // MARK: - Connection Check

    private func checkExistingConnection() {
        guard let uid = authManager.currentUser?.uid else {
            isCheckingConnection = false
            return
        }
        isCheckingConnection = true

        Task {
            do {
                try await FirebaseManager.shared.ensureUserDocument(uid: uid)
                if let partnerUid = try await FirebaseManager.shared.checkConnection(uid: uid) {
                    // User is connected — check if we have encryption keys
                    if KeyExchangeManager.shared.hasSymmetricKey {
                        // Keys available — go straight to connected
                        displayNameComplete = true
                        isConnected = true
                    } else {
                        // Try to derive keys (private key might be in Keychain already)
                        let derived = (try? await FirebaseManager.shared.completeKeyExchange(
                            partnerUid: partnerUid
                        )) ?? false

                        displayNameComplete = true

                        if derived && KeyExchangeManager.shared.hasSymmetricKey {
                            // Successfully derived — go to connected
                            isConnected = true
                        } else {
                            // Keys not available yet — show sync screen
                            partnerUidForSync = partnerUid
                            needsKeySync = true
                        }
                    }
                }
            } catch {
                // Offline or error — proceed without connection
            }
            isCheckingConnection = false
        }
    }
}
