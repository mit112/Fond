//
//  ContextualCardView.swift
//  Fond
//
//  Smart contextual card that surfaces the most relevant secondary content.
//  Swipeable horizontal paging with custom page dots.
//  Card types: daily prompt, heartbeat, sent echo, nudge received, both answered.
//

import SwiftUI

// MARK: - Card Type

enum ContextualCardType: Identifiable {
    case dailyPrompt(text: String)
    case heartbeat(bpm: Int, time: Date)
    case sentEcho(message: String)
    case nudgeReceived(partnerName: String)
    case bothAnswered

    var id: String {
        switch self {
        case .dailyPrompt: "prompt"
        case .heartbeat: "heartbeat"
        case .sentEcho: "echo"
        case .nudgeReceived: "nudge"
        case .bothAnswered: "bothAnswered"
        }
    }

    var icon: String {
        switch self {
        case .dailyPrompt: "💬"
        case .heartbeat: "❤️"
        case .sentEcho: "✓"
        case .nudgeReceived: "💛"
        case .bothAnswered: "✨"
        }
    }

    var tintColor: Color {
        switch self {
        case .heartbeat: FondColors.rose
        default: FondColors.amber
        }
    }
}

// MARK: - Contextual Card View

struct ContextualCardView: View {
    let cards: [ContextualCardType]
    let onTapPrompt: () -> Void

    @State private var selectedIndex = 0

    var body: some View {
        if cards.isEmpty { EmptyView() } else {
            VStack(spacing: 6) {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        cardContent(card)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(minHeight: 70)
                .onChange(of: cards.count) { _, newCount in
                    if selectedIndex >= newCount {
                        selectedIndex = max(0, newCount - 1)
                    }
                }

                if cards.count > 1 {
                    PageDotsView(
                        count: cards.count,
                        activeIndex: selectedIndex,
                        activeColor: cards.indices.contains(selectedIndex)
                            ? cards[selectedIndex].tintColor
                            : FondColors.amber
                    )
                }
            }
        }
    }

    // MARK: - Card Content

    @ViewBuilder
    private func cardContent(_ card: ContextualCardType) -> some View {
        let tint = card.tintColor
        Button {
            handleTap(card)
        } label: {
            HStack(spacing: 10) {
                Text(card.icon)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(cardLabel(card))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .tracking(0.3)

                    Text(cardSubtitle(card))
                        .font(.callout)
                        .foregroundStyle(FondColors.text.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()

                if isTappable(card) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FondColors.textSecondary.opacity(0.15))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isTappable(card))
    }

    // MARK: - Helpers

    private func cardLabel(_ card: ContextualCardType) -> String {
        switch card {
        case .dailyPrompt: "TODAY'S QUESTION"
        case .heartbeat: "HEARTBEAT"
        case .sentEcho: "SENT"
        case .nudgeReceived: "THINKING OF YOU"
        case .bothAnswered: "ANSWERS READY"
        }
    }

    private func cardSubtitle(_ card: ContextualCardType) -> String {
        switch card {
        case .dailyPrompt(let text): text
        case .heartbeat(let bpm, let time):
            "\(bpm) bpm • \(time.shortTimeAgo)"
        case .sentEcho(let message): "You: \(message)"
        case .nudgeReceived(let name): "\(name) is thinking of you"
        case .bothAnswered: "Tap to reveal answers"
        }
    }

    private func isTappable(_ card: ContextualCardType) -> Bool {
        switch card {
        case .dailyPrompt, .bothAnswered: true
        default: false
        }
    }

    private func handleTap(_ card: ContextualCardType) {
        switch card {
        case .dailyPrompt, .bothAnswered:
            onTapPrompt()
        default:
            break
        }
    }
}
