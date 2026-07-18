import SwiftUI

#if os(watchOS)
import WatchKit
#endif

struct FondField: View {
    var body: some View {
        FondColors.field.ignoresSafeArea()
    }
}

// Onboarding keeps its calm animated field while the connected experience uses FondField.
struct FondOnboardingBackground: View {
    #if os(watchOS)
    var body: some View {
        LinearGradient(
            colors: [FondColors.Mesh.topLeft, FondColors.Mesh.center, FondColors.Mesh.bottomRight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    #else
    @State private var phase = false

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                SIMD2(0, 0.5), SIMD2(phase ? 0.65 : 0.35, phase ? 0.55 : 0.45), SIMD2(1, 0.5),
                SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
            ],
            colors: [
                FondColors.Mesh.topLeft, FondColors.field, FondColors.Mesh.topRight,
                FondColors.Mesh.bottomLeft,
                phase ? FondColors.Mesh.centerAlt : FondColors.Mesh.center,
                FondColors.Mesh.topRight,
                phase ? FondColors.Mesh.bottomLeftAlt : FondColors.Mesh.bottomLeft,
                FondColors.Mesh.center,
                FondColors.Mesh.bottomRight,
            ]
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
    #endif
}

private struct FondBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(FondColors.field.ignoresSafeArea())
    }
}

private struct FondKeepsakeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: FondGeometry.cardCornerRadius,
            style: .continuous
        )
        content
            .clipShape(shape)
            .background {
                shape
                    .fill(FondColors.keepsake)
                    .overlay {
                        shape.strokeBorder(
                            FondColors.amber,
                            lineWidth: contrast == .increased ? 2 : 1.25
                        )
                    }
                    .overlay {
                        shape
                            .inset(by: 3)
                            .strokeBorder(FondColors.ink.opacity(0.06), lineWidth: 0.5)
                    }
                    .shadow(
                        color: FondColors.shadow.opacity(colorScheme == .dark ? 0.38 : 0.16),
                        radius: colorScheme == .dark ? 46 : 38,
                        y: colorScheme == .dark ? 18 : 16
                    )
            }
    }
}

private struct FondFloatingControlModifier<ControlShape: Shape>: ViewModifier {
    let shape: ControlShape
    let tinted: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(tinted ? FondColors.amber : FondColors.controlFallback))
                .overlay(shape.stroke(FondColors.rule, lineWidth: 1))
                .shadow(color: FondColors.shadow.opacity(0.16), radius: 16, y: 6)
        } else if tinted {
            content.glassEffect(.regular.tint(FondColors.amber).interactive(), in: shape)
        } else {
            content.glassEffect(.regular.interactive(), in: shape)
        }
    }
}

private struct FondControlPlateModifier<ControlShape: Shape>: ViewModifier {
    let shape: ControlShape
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(shape.fill(FondColors.controlPlate))
            .overlay {
                if contrast == .increased {
                    shape.stroke(FondColors.rule, lineWidth: 1.5)
                }
            }
    }
}

private struct FondSendControlModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Circle().fill(FondColors.amber))
                .overlay(Circle().stroke(FondColors.rule, lineWidth: 1))
                .shadow(color: FondColors.shadow.opacity(0.16), radius: 16, y: 6)
        } else {
            content.glassEffect(.regular.tint(FondColors.amber).interactive(), in: Circle())
        }
    }
}

extension View {
    func fondBackground() -> some View {
        modifier(FondBackgroundModifier())
    }

    func fondKeepsakeCard() -> some View {
        modifier(FondKeepsakeModifier())
    }

    func fondFloatingControl(
        in shape: some Shape = Capsule(),
        tinted: Bool = false
    ) -> some View {
        modifier(FondFloatingControlModifier(shape: shape, tinted: tinted))
    }

    func fondControlPlate(in shape: some Shape = Capsule()) -> some View {
        modifier(FondControlPlateModifier(shape: shape))
    }

    func fondSendControl() -> some View {
        modifier(FondSendControlModifier())
    }

}

enum FondHaptics {
    #if os(iOS)
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()
    #endif

    static func faceTurned() {
        #if os(iOS)
        selection.selectionChanged()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.directionUp)
        #endif
    }

    static func statusChanged() {
        #if os(iOS)
        impactLight.impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    static func nudgeSent() {
        #if os(iOS)
        impactLight.impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    static func messageSent() {
        #if os(iOS)
        impactMedium.impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    static func partnerUpdated() {
        #if os(iOS)
        notification.notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }

    static func pairingSuccess() {
        #if os(iOS)
        notification.notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    static func error() {
        #if os(iOS)
        notification.notificationOccurred(.error)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.failure)
        #endif
    }

    static func warning() {
        #if os(iOS)
        notification.notificationOccurred(.warning)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.retry)
        #endif
    }
}

extension Animation {
    static let fondSpring = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let fondQuick = Animation.spring(response: 0.3, dampingFraction: 0.75)
}

#Preview("Ember Folio card") {
    ZStack {
        FondField()
        Text("Maya")
            .font(FondType.partnerName)
            .foregroundStyle(FondColors.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(FondSpacing.six)
            .fondKeepsakeCard()
            .padding(FondGeometry.cardMarginCompact)
    }
}
