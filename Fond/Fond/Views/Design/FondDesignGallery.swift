#if DEBUG
import SwiftUI

struct FondDesignGallery: View {
    @State private var activeFace: FondFace
    @State private var fixture: Fixture
    @State private var isCardDragging = false
    @State private var messageText = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let initialFixture = Fixture(arguments: arguments)
        _fixture = State(initialValue: initialFixture)
        _activeFace = State(initialValue: initialFixture.initialFace)
    }

    var body: some View {
        ZStack {
            FondField()

            VStack(spacing: FondSpacing.three) {
                galleryToolbar

                galleryCard
                    .frame(maxWidth: FondGeometry.contentMaxWidth, maxHeight: .infinity)

                PageDotsView(count: 2, activeIndex: displayedFace.rawValue)
                    .accessibilityLabel(displayedFace == .now ? "Now face" : "Together face")

                ConnectedMessageInput(
                    messageText: $messageText,
                    myStatus: .available,
                    isSending: false,
                    sendSuccess: false,
                    cooldownRemaining: 0,
                    errorMessage: nil,
                    onSend: {},
                    onStatusTap: {}
                )
                .frame(maxWidth: FondGeometry.contentMaxWidth)
            }
            .padding(.horizontal, cardMargin)
            .padding(.top, FondSpacing.two)
            .padding(.bottom, FondSpacing.three)
        }
        .dynamicTypeSize(fixture == .ax5 ? .accessibility5 : systemDynamicTypeSize)
        .preferredColorScheme(preferredColorScheme)
    }

    @ViewBuilder
    private var galleryCard: some View {
        if fixture == .midTurn {
            GalleryMidTurnCard(
                now: nowFace,
                together: togetherFace,
                angle: 67
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fond.card")
        } else {
            CardTurnContainer(
                face: $activeFace,
                isDragging: $isCardDragging,
                reduceMotion: reduceMotion,
                front: { nowFace },
                back: { togetherFace }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fond.card")
        }
    }

    private var nowFace: some View {
        NowFaceView(model: nowModel, isBreathing: false, onNudge: {})
            .fondKeepsakeCard()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fond.face.now")
    }

    private var togetherFace: some View {
        TogetherFaceView(
            state: ritualState,
            moments: galleryMoments,
            hasMore: false,
            onAnswer: { _ in },
            onLoadMore: {}
        )
        .fondKeepsakeCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fond.face.together")
    }

    private var galleryToolbar: some View {
        HStack(spacing: FondSpacing.two) {
            Menu {
                ForEach(Fixture.allCases) { option in
                    Button(option.label) { select(option) }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.medium))
                    .foregroundStyle(FondColors.ink)
                    .frame(width: FondGeometry.minimumTarget, height: FondGeometry.minimumTarget)
            }
            .accessibilityLabel("Choose gallery fixture")

            Spacer(minLength: FondSpacing.one)

            HStack(spacing: FondSpacing.two) {
                faceButton("Now", face: .now)
                Text("·")
                    .font(FondType.control)
                    .foregroundStyle(FondColors.amber)
                    .accessibilityHidden(true)
                faceButton("Together", face: .together)
            }
            .padding(.horizontal, FondSpacing.four)
            .frame(height: 36)
            .fondControlPlate(in: Capsule())

            Spacer(minLength: FondSpacing.one)

            Button {
                select(.togetherRevealed)
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
        .frame(maxWidth: FondGeometry.contentMaxWidth)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fond.toolbar")
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func faceButton(_ label: String, face: FondFace) -> some View {
        Button {
            activeFace = face
            fixture = face == .now ? .now : .togetherRevealed
        } label: {
            Text(label)
                .font(FondType.control)
                .foregroundStyle(displayedFace == face ? FondColors.ink : FondColors.inkSecondary)
                .frame(minHeight: FondGeometry.minimumTarget)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(displayedFace == face ? .isSelected : [])
    }

    private func select(_ option: Fixture) {
        fixture = option
        activeFace = option.initialFace
    }

    private var displayedFace: FondFace {
        fixture == .midTurn ? .now : activeFace
    }

    private var cardMargin: CGFloat {
        horizontalSizeClass == .regular
            ? FondGeometry.cardMarginRegular
            : FondGeometry.cardMarginCompact
    }

    private var preferredColorScheme: ColorScheme? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-FondGalleryAppearance"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1].lowercased() == "dark" ? .dark : .light
    }

    private var nowModel: NowFaceModel {
        let isStale = fixture == .stale
        return NowFaceModel(
            partnerName: fixture == .longName ? "Alexandria-Rose" : "Maya",
            status: isStale ? .away : .available,
            message: isStale
                ? "Made it home. Call me when the morning reaches you."
                : "I saved you the window seat. Lisbon is starting to feel real.",
            lastUpdated: .now.addingTimeInterval(isStale ? -10_800 : -360),
            heartbeatBpm: isStale ? nil : 72,
            heartbeatTime: isStale ? nil : .now.addingTimeInterval(-540),
            distanceMiles: 1_284,
            relationshipLine: "412 days together · 18 until Lisbon",
            isStale: isStale
        )
    }

    private var ritualState: TodayRitualState {
        let phase: TodayRitualState.Phase
        switch fixture {
        case .togetherUnanswered, .empty:
            phase = .unanswered
        default:
            phase = .revealed(
                myAnswer: "The train pulling in.",
                partnerAnswer: "Coffee before the city wakes."
            )
        }
        return TodayRitualState(
            question: "What's one small thing you're looking forward to?",
            partnerName: "Maya",
            phase: phase,
            isSubmitting: false,
            errorMessage: nil
        )
    }

    private var galleryMoments: [TogetherMoment] {
        guard fixture != .empty else { return [] }
        let now = Date.now
        return [
            TogetherMoment(
                id: "gallery-message-partner",
                timestamp: now.addingTimeInterval(-900),
                kind: .message(text: "I saved you the window seat.", author: .partner)
            ),
            TogetherMoment(
                id: "gallery-message-me",
                timestamp: now.addingTimeInterval(-1_500),
                kind: .message(text: "Then I'm bringing the coffee.", author: .me)
            ),
            TogetherMoment(
                id: "gallery-nudge",
                timestamp: now.addingTimeInterval(-2_100),
                kind: .nudge(author: .partner)
            ),
            TogetherMoment(
                id: "gallery-status",
                timestamp: now.addingTimeInterval(-3_600),
                kind: .status(status: .sleeping, label: "Sleeping", author: .partner)
            ),
            TogetherMoment(
                id: "gallery-question",
                timestamp: now.addingTimeInterval(-90_000),
                kind: .answeredQuestion(
                    question: "What ordinary moment would you keep?",
                    myAnswer: "The walk home",
                    partnerAnswer: "Morning coffee"
                )
            ),
        ]
    }
}

private extension FondDesignGallery {
    enum Fixture: String, CaseIterable, Identifiable {
        case now
        case togetherUnanswered
        case togetherRevealed
        case midTurn
        case stale
        case empty
        case longName
        case ax5

        var id: Self { self }

        var label: String {
            switch self {
            case .now: "Now"
            case .togetherUnanswered: "Together — unanswered"
            case .togetherRevealed: "Together — revealed"
            case .midTurn: "Mid-turn — 67°"
            case .stale: "Stale"
            case .empty: "Empty"
            case .longName: "Long name"
            case .ax5: "AX5"
            }
        }

        var initialFace: FondFace {
            switch self {
            case .togetherUnanswered, .togetherRevealed, .empty:
                .together
            default:
                .now
            }
        }

        init(arguments: [String]) {
            guard let index = arguments.firstIndex(of: "-FondGalleryFixture"),
                  arguments.indices.contains(index + 1),
                  let fixture = Self(rawValue: arguments[index + 1]) else {
                self = .now
                return
            }
            self = fixture
        }
    }
}

private struct GalleryMidTurnCard<Now: View, Together: View>: View {
    let now: Now
    let together: Together
    let angle: Double

    var body: some View {
        ZStack {
            now
                .opacity(angle < 90 ? 1 : 0)
                .rotation3DEffect(
                    .degrees(angle),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 1 / 850
                )
            together
                .opacity(angle > 90 ? 1 : 0)
                .rotation3DEffect(
                    .degrees(angle - 180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 1 / 850
                )
        }
    }
}
#endif
