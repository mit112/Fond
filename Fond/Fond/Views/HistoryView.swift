//
//  HistoryView.swift
//  Fond
//
//  Chat-bubble history feed of status changes and messages.
//  Warm-colored bubbles: amber for mine, lavender for partner's.
//  Grouped by day with date separators.
//
//  Design reference: docs/02-design-direction.md
//

import SwiftUI
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct HistoryView: View {
    let connectionId: String
    let myUid: String

    @State private var entries: [FondMessage] = []
    @State private var isLoading = true
    @State private var lastDocument: DocumentSnapshot?
    @State private var hasMore = true
    @State private var isLoadingMore = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ZStack {
                        FondColors.background.ignoresSafeArea()
                        ProgressView()
                    }
                } else if entries.isEmpty {
                    ZStack {
                        FondColors.background.ignoresSafeArea()
                        ContentUnavailableView(
                            "No history yet",
                            systemImage: "clock",
                            description: Text("Status changes and messages will appear here.")
                        )
                    }
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(FondColors.amber)
                }
            }
        }
        .task { await loadHistory() }
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(groupedByDay, id: \.date) { group in
                        // Day separator
                        daySeparator(group.date)
                            .padding(.top, 12)
                            .padding(.bottom, 4)

                        // Entries for this day
                        ForEach(group.entries) { entry in
                            historyBubble(entry)
                                .id(entry.id)
                        }
                    }

                    // Load more
                    if hasMore {
                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else {
                            Button {
                                Task { await loadMore() }
                            } label: {
                                Text("Load More")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(FondColors.amber)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .fondBackground()
            .onAppear {
                // Scroll to bottom (newest)
                if let lastId = entries.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Day Separator

    private func daySeparator(_ date: Date) -> some View {
        Text(dayLabel(for: date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(FondColors.textSecondary)
            .frame(maxWidth: .infinity)
    }

    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }

    // MARK: - Chat Bubble

    @ViewBuilder
    private func historyBubble(_ entry: FondMessage) -> some View {
        let isMe = entry.authorUid == myUid
        let decrypted = EncryptionManager.shared.decryptOrNil(entry.encryptedPayload)

        HStack {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                // Content — route by entry type
                switch entry.type {
                case .status:
                    if let raw = decrypted {
                        let info = UserStatus.displayInfo(forRawValue: raw)
                        compactPill(icon: info.emoji, label: info.displayName)
                    }

                case .nudge:
                    compactPill(
                        icon: "💛",
                        label: isMe ? "You’re thinking of them" : "Thinking of you",
                        tint: FondColors.amber
                    )

                case .heartbeat:
                    if let json = decrypted,
                       let data = json.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let bpm = dict["bpm"] as? Int {
                        compactPill(
                            icon: "❤️",
                            label: "\(bpm) bpm",
                            tint: FondColors.rose
                        )
                    } else {
                        compactPill(icon: "❤️", label: "Heartbeat")
                    }

                case .promptAnswer:
                    if let json = decrypted,
                       let data = json.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let answer = dict["answer"] as? String {
                        VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                            Text("💬 Daily Prompt")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(FondColors.textSecondary)
                            messageBubble(text: answer, isMe: isMe)
                        }
                    } else {
                        messageBubble(text: decrypted ?? "[encrypted]", isMe: isMe)
                    }

                case .message:
                    messageBubble(text: decrypted ?? "[encrypted]", isMe: isMe)
                }

                // Timestamp
                Text(entry.timestamp.historyTimestamp)
                    .font(.caption2)
                    .foregroundStyle(FondColors.textSecondary.opacity(0.7))
                    .padding(.horizontal, 4)
            }

            if !isMe { Spacer(minLength: 60) }
        }
    }

    // MARK: - Reusable Components

    private func compactPill(icon: String, label: String, tint: Color = FondColors.surface) -> some View {
        HStack(spacing: 6) {
            Text(icon)
                .font(.subheadline)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(FondColors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(tint.opacity(0.15))
        )
    }

    private func messageBubble(text: String, isMe: Bool) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(FondColors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isMe ? FondColors.bubbleMine : FondColors.bubblePartner)
            )
    }

    // MARK: - Grouped Data

    private struct DayGroup {
        let date: Date
        let entries: [FondMessage]
    }

    /// Groups entries by calendar day for date separators.
    private var groupedByDay: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        return grouped
            .sorted { $0.key < $1.key }
            .map { DayGroup(date: $0.key, entries: $0.value) }
    }

    // MARK: - Data Loading

    private func loadHistory() async {
        isLoadingMore = false
        do {
            let result = try await FirebaseManager.shared.fetchHistory(connectionId: connectionId)
            entries = result.entries
            lastDocument = result.lastDocument
            hasMore = result.lastDocument != nil
        } catch {
            // Silently fail — show empty state
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let result = try await FirebaseManager.shared.fetchHistory(
                connectionId: connectionId,
                startAfter: lastDocument
            )
            entries.append(contentsOf: result.entries)
            lastDocument = result.lastDocument
            hasMore = result.lastDocument != nil
        } catch {
            // Silently fail — keep existing entries
        }
        isLoadingMore = false
    }
}
