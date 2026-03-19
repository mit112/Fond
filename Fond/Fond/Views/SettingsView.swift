//
//  SettingsView.swift
//  Fond
//
//  Account settings — display name change, disconnect, sign out.
//  Minimal glass-styled list with warm background.
//
//  Design reference: docs/02-design-direction.md
//

import SwiftUI
import WidgetKit
import FirebaseAuth

struct SettingsView: View {
    var authManager: AuthManager
    var connectionId: String?
    var onDisconnect: () -> Void

    @State private var showUnlinkConfirm = false
    @State private var isUnlinking = false
    @State private var showNameEdit = false
    @State private var newName = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    // MARK: - Date Settings

    @State private var anniversaryDate: Date = .now
    @State private var hasAnniversary = false
    @State private var countdownDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: .now)!
    @State private var hasCountdown = false
    @State private var countdownLabel = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let user = authManager.currentUser {
                        Button {
                            newName = user.displayName ?? ""
                            showNameEdit = true
                        } label: {
                            HStack {
                                Label("Name", systemImage: "person")
                                    .foregroundStyle(FondColors.text)
                                Spacer()
                                Text(user.displayName ?? "—")
                                    .foregroundStyle(FondColors.textSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(FondColors.textSecondary.opacity(0.5))
                            }
                        }

                        HStack {
                            Label("Email", systemImage: "envelope")
                                .foregroundStyle(FondColors.text)
                            Spacer()
                            Text(user.email ?? "Hidden")
                                .foregroundStyle(FondColors.textSecondary)
                        }
                    }
                } header: {
                    Text("Account")
                }

                // MARK: - Dates Section

                Section {
                    Toggle(isOn: $hasAnniversary) {
                        Label("Anniversary", systemImage: "heart.circle")
                            .foregroundStyle(FondColors.text)
                    }
                    .tint(FondColors.amber)
                    .onChange(of: hasAnniversary) { saveDates() }

                    if hasAnniversary {
                        DatePicker(
                            "Date",
                            selection: $anniversaryDate,
                            in: ...Date.now,
                            displayedComponents: .date
                        )
                        .tint(FondColors.amber)
                        .onChange(of: anniversaryDate) { saveDates() }
                    }

                    Toggle(isOn: $hasCountdown) {
                        Label("Countdown", systemImage: "calendar.badge.clock")
                            .foregroundStyle(FondColors.text)
                    }
                    .tint(FondColors.amber)
                    .onChange(of: hasCountdown) { saveDates() }

                    if hasCountdown {
                        DatePicker(
                            "Date",
                            selection: $countdownDate,
                            in: Date.now...,
                            displayedComponents: .date
                        )
                        .tint(FondColors.amber)
                        .onChange(of: countdownDate) { saveDates() }

                        TextField("Label (e.g. NYC trip)", text: $countdownLabel)
                            .onChange(of: countdownLabel) { saveDates() }
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    Text("Shown on your Days Together widget.")
                }

                Section {
                    Button {
                        showUnlinkConfirm = true
                    } label: {
                        HStack {
                            Label("Disconnect from partner", systemImage: "person.slash")
                            Spacer()
                            if isUnlinking {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .foregroundStyle(FondColors.rose)
                    .disabled(isUnlinking)
                } header: {
                    Text("Connection")
                }

                Section {
                    Button {
                        signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .foregroundStyle(FondColors.rose)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(FondColors.rose)
                            .font(.caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .fondBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(FondColors.amber)
                }
            }
            .confirmationDialog(
                "Disconnect from your partner?",
                isPresented: $showUnlinkConfirm,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    unlink()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your connection will end and encryption keys will be deleted. You can reconnect later with a new code.")
            }
            .onAppear { loadDates() }
            .alert("Change Name", isPresented: $showNameEdit) {
                TextField("Your name", text: $newName)
                Button("Save") { saveName() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is what your partner sees on their widgets.")
            }
        }
    }

    // MARK: - Lifecycle

    private func loadDates() {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else { return }
        if let date = defaults.object(forKey: FondConstants.anniversaryDateKey) as? Date {
            anniversaryDate = date
            hasAnniversary = true
        }
        if let date = defaults.object(forKey: FondConstants.countdownDateKey) as? Date {
            countdownDate = date
            hasCountdown = true
        }
        countdownLabel = defaults.string(forKey: FondConstants.countdownLabelKey) ?? ""
    }

    private func saveDates() {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else { return }

        // Write to App Group for widgets
        if hasAnniversary {
            defaults.set(anniversaryDate, forKey: FondConstants.anniversaryDateKey)
        } else {
            defaults.removeObject(forKey: FondConstants.anniversaryDateKey)
        }

        if hasCountdown {
            defaults.set(countdownDate, forKey: FondConstants.countdownDateKey)
            defaults.set(countdownLabel, forKey: FondConstants.countdownLabelKey)
        } else {
            defaults.removeObject(forKey: FondConstants.countdownDateKey)
            defaults.removeObject(forKey: FondConstants.countdownLabelKey)
        }

        WidgetCenter.shared.reloadAllTimelines()
        Task { await FondRelevanceUpdater.update() }

        // Sync to Firestore so partner sees the same data
        Task {
            do {
                // Anniversary → connection doc (shared)
                if let cid = connectionId {
                    try await FirebaseManager.shared.setAnniversaryDate(
                        connectionId: cid,
                        date: hasAnniversary ? anniversaryDate : nil
                    )
                }
                // Countdown → user doc (personal)
                if let uid = authManager.currentUser?.uid {
                    try await FirebaseManager.shared.setCountdownDate(
                        uid: uid,
                        date: hasCountdown ? countdownDate : nil,
                        label: hasCountdown ? countdownLabel : nil
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Actions

    private func unlink() {
        isUnlinking = true
        errorMessage = nil
        FondHaptics.warning()

        Task {
            do {
                try await FirebaseManager.shared.callUnlinkConnection()
                try? KeychainManager.shared.deleteAllKeys()
                clearWidgetData()
                dismiss()
                onDisconnect()
            } catch {
                errorMessage = error.localizedDescription
            }
            isUnlinking = false
        }
    }

    private func signOut() {
        authManager.signOut()
        try? KeychainManager.shared.deleteAllKeys()
        if let defaults = UserDefaults(suiteName: FondConstants.appGroupID) {
            defaults.set(
                ConnectionState.signedOut.rawValue,
                forKey: FondConstants.connectionStateKey
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
        Task { await FondRelevanceUpdater.update() }
        dismiss()
    }

    private func saveName() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 30 else { return }

        Task {
            do {
                try await authManager.updateDisplayName(trimmed)
                guard let uid = authManager.currentUser?.uid else { return }
                let encryptedName = try EncryptionManager.shared.encrypt(trimmed)
                try await FirebaseManager.shared.updateEncryptedName(
                    uid: uid,
                    encryptedName: encryptedName
                )
                FondHaptics.statusChanged()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearWidgetData() {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else { return }
        defaults.removeObject(forKey: FondConstants.partnerNameKey)
        defaults.removeObject(forKey: FondConstants.partnerStatusKey)
        defaults.removeObject(forKey: FondConstants.partnerMessageKey)
        defaults.removeObject(forKey: FondConstants.partnerLastUpdatedKey)
        defaults.removeObject(forKey: FondConstants.anniversaryDateKey)
        defaults.removeObject(forKey: FondConstants.countdownDateKey)
        defaults.removeObject(forKey: FondConstants.countdownLabelKey)
        defaults.removeObject(forKey: FondConstants.distanceMilesKey)
        defaults.removeObject(forKey: FondConstants.partnerCityKey)
        defaults.removeObject(forKey: FondConstants.partnerHeartbeatKey)
        defaults.removeObject(forKey: FondConstants.partnerHeartbeatTimeKey)
        defaults.removeObject(forKey: FondConstants.partnerPromptAnswerKey)
        defaults.removeObject(forKey: FondConstants.dailyPromptIdKey)
        defaults.removeObject(forKey: FondConstants.dailyPromptTextKey)
        defaults.removeObject(forKey: FondConstants.myPromptAnswerKey)
        defaults.set(
            ConnectionState.unpaired.rawValue,
            forKey: FondConstants.connectionStateKey
        )
        WidgetCenter.shared.reloadAllTimelines()
        Task { await FondRelevanceUpdater.update() }
    }
}
