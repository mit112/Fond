import SwiftUI

enum FondFace: Int, CaseIterable, Sendable, Hashable {
    case now
    case together
}

enum CardTurnMath {
    static let widthFactor: CGFloat = 0.88
    static let commitProgress: CGFloat = 0.42
    static let commitVelocity: CGFloat = 450

    static func progress(translation: CGFloat, width: CGFloat, from face: FondFace) -> CGFloat {
        guard width > 0 else { return 0 }
        let directed = face == .now ? -translation : translation
        return min(max(directed / (width * widthFactor), 0), 1)
    }

    static func angle(progress: CGFloat, from face: FondFace) -> Double {
        face == .now ? Double(progress * 180) : Double(180 - progress * 180)
    }

    static func destination(progress: CGFloat, velocity: CGFloat, from face: FondFace) -> FondFace {
        let velocityCommits = face == .now
            ? velocity < -commitVelocity
            : velocity > commitVelocity
        guard progress >= commitProgress || velocityCommits else { return face }
        return face == .now ? .together : .now
    }
}

struct CardTurnContainer<Front: View, Back: View>: View {
    @Binding private var face: FondFace
    let reduceMotion: Bool
    private let front: Front
    private let back: Back

    @State private var angle: Double
    @State private var dragOrigin: FondFace?
    @State private var crossedMidpoint = false
    @State private var accessibilityFace: FondFace
    @State private var reducedFace: FondFace
    @State private var reducedOpacity = 1.0
    @AccessibilityFocusState private var focusedFace: FondFace?

    init(
        face: Binding<FondFace>,
        reduceMotion: Bool,
        @ViewBuilder front: () -> Front,
        @ViewBuilder back: () -> Back
    ) {
        _face = face
        self.reduceMotion = reduceMotion
        self.front = front()
        self.back = back()
        let initialFace = face.wrappedValue
        _angle = State(initialValue: initialFace == .now ? 0 : 180)
        _accessibilityFace = State(initialValue: initialFace)
        _reducedFace = State(initialValue: initialFace)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                front
                    .opacity(frontOpacity)
                    .rotation3DEffect(
                        .degrees(reduceMotion ? 0 : angle),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 1 / 850
                    )
                    .accessibilityHidden(accessibilityFace != .now)
                    .accessibilityFocused($focusedFace, equals: .now)

                back
                    .opacity(backOpacity)
                    .rotation3DEffect(
                        .degrees(reduceMotion ? 0 : angle - 180),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 1 / 850
                    )
                    .accessibilityHidden(accessibilityFace != .together)
                    .accessibilityFocused($focusedFace, equals: .together)
            }
            .overlay(alignment: face == .now ? .trailing : .leading) {
                Capsule()
                    .fill(FondColors.amber)
                    .frame(width: 7, height: 54)
                    .offset(x: face == .now ? 4 : -4)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(turnGesture(width: proxy.size.width))
        }
        .onChange(of: face) { oldFace, newFace in
            guard oldFace != newFace, dragOrigin == nil else { return }
            settle(to: newFace, focus: true)
        }
    }

    private var frontOpacity: Double {
        if reduceMotion {
            return reducedFace == .now ? reducedOpacity : 0
        }
        return angle < 90 ? 1 : 0
    }

    private var backOpacity: Double {
        if reduceMotion {
            return reducedFace == .together ? reducedOpacity : 0
        }
        return angle > 90 ? 1 : 0
    }

    private func turnGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.height) <= abs(value.translation.width) * 1.2 else {
                    return
                }
                let origin = dragOrigin ?? face
                if dragOrigin == nil {
                    dragOrigin = origin
                    crossedMidpoint = false
                }
                let progress = CardTurnMath.progress(
                    translation: value.translation.width,
                    width: width,
                    from: origin
                )
                if !reduceMotion {
                    angle = CardTurnMath.angle(progress: progress, from: origin)
                }
                accessibilityFace = progress < 0.5 ? origin : origin.opposite
                if progress >= 0.5, !crossedMidpoint {
                    crossedMidpoint = true
                    FondHaptics.faceTurned()
                }
            }
            .onEnded { value in
                let origin = dragOrigin ?? face
                defer { dragOrigin = nil }
                guard abs(value.translation.height) <= abs(value.translation.width) * 1.2 else {
                    settle(to: origin, focus: false)
                    return
                }
                let progress = CardTurnMath.progress(
                    translation: value.translation.width,
                    width: width,
                    from: origin
                )
                let destination = CardTurnMath.destination(
                    progress: progress,
                    velocity: value.velocity.width,
                    from: origin
                )
                if destination != origin, !crossedMidpoint {
                    FondHaptics.faceTurned()
                }
                face = destination
                let directedVelocity = origin == .now
                    ? -value.velocity.width
                    : value.velocity.width
                settle(
                    to: destination,
                    focus: destination != origin,
                    initialVelocity: Double(directedVelocity / max(width, 1))
                )
            }
    }

    private func settle(
        to destination: FondFace,
        focus: Bool,
        initialVelocity: Double = 0
    ) {
        if reduceMotion {
            crossfade(to: destination, focus: focus)
            return
        }
        let targetAngle = destination == .now ? 0.0 : 180.0
        withAnimation(
            .interpolatingSpring(
                mass: 1,
                stiffness: 330,
                damping: 32,
                initialVelocity: initialVelocity
            )
        ) {
            angle = targetAngle
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(460))
            accessibilityFace = destination
            if focus { focusedFace = destination }
        }
    }

    private func crossfade(to destination: FondFace, focus: Bool) {
        Task { @MainActor in
            withAnimation(.linear(duration: 0.09)) {
                reducedOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(90))
            reducedFace = destination
            angle = destination == .now ? 0 : 180
            accessibilityFace = destination
            withAnimation(.linear(duration: 0.12)) {
                reducedOpacity = 1
            }
            if focus {
                try? await Task.sleep(for: .milliseconds(120))
                focusedFace = destination
            }
        }
    }
}

private extension FondFace {
    var opposite: FondFace {
        self == .now ? .together : .now
    }
}

private struct CardTurnAnglePreview: View {
    let angle: Double

    var body: some View {
        ZStack {
            previewFace("Now")
                .opacity(angle < 90 ? 1 : 0)
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 1 / 850)
            previewFace("Together")
                .opacity(angle > 90 ? 1 : 0)
                .rotation3DEffect(.degrees(angle - 180), axis: (x: 0, y: 1, z: 0), perspective: 1 / 850)
        }
        .frame(width: 320, height: 480)
        .fondKeepsakeCard()
        .padding()
        .background(FondColors.field)
    }

    private func previewFace(_ title: String) -> some View {
        Text(title)
            .font(FondType.question)
            .foregroundStyle(FondColors.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Card turn primitives") {
    @Previewable @State var face = FondFace.now
    CardTurnContainer(face: $face, reduceMotion: false) {
        Text("Now").frame(maxWidth: .infinity, maxHeight: .infinity)
    } back: {
        Text("Together").frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 320, height: 480)
    .fondKeepsakeCard()
    .padding()
    .background(FondColors.field)
}

#Preview("Turn 0 degrees") { CardTurnAnglePreview(angle: 0) }
#Preview("Turn 67 degrees") { CardTurnAnglePreview(angle: 67) }
#Preview("Turn 90 degrees") { CardTurnAnglePreview(angle: 90) }
#Preview("Turn 180 degrees") { CardTurnAnglePreview(angle: 180) }
