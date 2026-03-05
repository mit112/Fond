//
//  FondTheme.swift
//  Fond
//
//  Reusable view components and modifiers for the Fond design system.
//  Contains: Animated mesh gradient, glass helpers, card styles.
//
//  Target membership: Fond (iOS/Mac) — NOT widget (widgets can't use MeshGradient).
//  watchOS gets a stripped-down version (no mesh gradient — too expensive).
//
//  Design reference: docs/02-design-direction.md
//

import SwiftUI
#if os(watchOS)
import WatchKit
#endif

// MARK: - Animated Mesh Gradient Background

/// A slowly animating warm mesh gradient that creates a "breathing" background.
/// Used on the connected view and onboarding screens.
///
/// Performance notes:
/// - MeshGradient is GPU-accelerated and efficient for this grid size.
/// - Animation uses easeInOut with 6s duration — low CPU impact.
/// - Only animates the center point position + 2 color shifts.
/// - Ignores safe area so it fills behind status bar and home indicator.
struct FondMeshGradient: View {
    #if os(watchOS)
    // watchOS: static warm gradient — no animation to save battery.
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
                // Row 0: top
                SIMD2(0.0, 0.0),
                SIMD2(0.5, 0.0),
                SIMD2(1.0, 0.0),
                // Row 1: middle — center point animates
                SIMD2(0.0, 0.5),
                SIMD2(phase ? 0.65 : 0.35, phase ? 0.55 : 0.45),
                SIMD2(1.0, 0.5),
                // Row 2: bottom
                SIMD2(0.0, 1.0),
                SIMD2(0.5, 1.0),
                SIMD2(1.0, 1.0),
            ],
            colors: [
                // Row 0
                FondColors.Mesh.topLeft,
                FondColors.background,
                FondColors.Mesh.topRight,
                // Row 1 — center color shifts
                FondColors.Mesh.bottomLeft,
                phase ? FondColors.Mesh.centerAlt : FondColors.Mesh.center,
                FondColors.Mesh.topRight,
                // Row 2 — bottom-left shifts
                phase ? FondColors.Mesh.bottomLeftAlt : FondColors.Mesh.bottomLeft,
                FondColors.Mesh.center,
                FondColors.Mesh.bottomRight,
            ]
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 6.0)
                .repeatForever(autoreverses: true)
            ) {
                phase = true
            }
        }
    }
    #endif
}

// MARK: - Fond Background Modifier

/// Applies the standard Fond background color to a view.
/// Use on screens that don't have the mesh gradient (settings, etc.).
struct FondBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(FondColors.background.ignoresSafeArea())
    }
}

extension View {
    /// Applies the standard Fond warm background.
    func fondBackground() -> some View {
        modifier(FondBackgroundModifier())
    }
}

// MARK: - Fond Card Modifier

/// Applies an elevated card style — Liquid Glass `.clear` on iOS 26,
/// falls back to surface color + shadow on earlier versions.
struct FondCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            content
                .glassEffect(
                    .clear,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(FondColors.surface.opacity(0.6))
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
                )
        }
    }
}

extension View {
    /// Applies the Fond card style — clear glass on iOS 26, surface + shadow on earlier.
    func fondCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(FondCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Helpers (iOS 26)

extension View {
    /// Applies Liquid Glass with amber tint on iOS 26, falls back to thin material.
    /// Use for primary interactive surfaces (send button, selected status).
    @ViewBuilder
    func fondGlass(
        in shape: some Shape = Capsule(),
        tinted: Bool = true
    ) -> some View {
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            let glass: Glass = tinted
                ? .regular.tint(FondColors.amber)
                : .regular
            self.glassEffect(glass, in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }

    /// Interactive Liquid Glass — for tappable buttons and controls.
    /// Adds press feedback (scale bounce + shimmer) on iOS 26.
    @ViewBuilder
    func fondGlassInteractive(
        in shape: some Shape = Capsule(),
        tinted: Bool = false
    ) -> some View {
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            let glass: Glass = tinted
                ? .regular.tint(FondColors.amber).interactive()
                : .regular.interactive()
            self.glassEffect(glass, in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }

    /// Applies Liquid Glass without tint on iOS 26, falls back to thin material.
    /// Use for secondary surfaces (toolbar items, unselected controls).
    @ViewBuilder
    func fondGlassPlain(in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }
}

// MARK: - Haptic Helpers

/// Centralized haptic feedback to ensure consistent feel across the app.
/// Uses UIKit feedback generators on iOS/iPadOS, WKHapticType on watchOS.
/// Generators are pre-allocated per type for zero-latency feedback.
enum FondHaptics {
    #if os(iOS)
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()
    #endif

    /// Status changed — light tap.
    static func statusChanged() {
        #if os(iOS)
        impactLight.impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    /// Message sent — medium tap.
    static func messageSent() {
        #if os(iOS)
        impactMedium.impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    /// Partner update received — subtle notification.
    static func partnerUpdated() {
        #if os(iOS)
        notification.notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }

    /// Pairing success — celebratory.
    static func pairingSuccess() {
        #if os(iOS)
        notification.notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    /// Error or blocked action.
    static func error() {
        #if os(iOS)
        notification.notificationOccurred(.error)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.failure)
        #endif
    }

    /// Destructive action confirmed (unlink).
    static func warning() {
        #if os(iOS)
        notification.notificationOccurred(.warning)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.retry)
        #endif
    }
}

// MARK: - Spring Animation Preset

extension Animation {
    /// Standard Fond spring for state transitions (partner data arriving, etc.).
    static let fondSpring = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// Quick spring for micro-interactions (button feedback, picker changes).
    static let fondQuick = Animation.spring(response: 0.3, dampingFraction: 0.75)
}

// MARK: - Previews

#Preview("Mesh Gradient") {
    FondMeshGradient()
}

#Preview("Card Style") {
    ZStack {
        FondMeshGradient()
        VStack(spacing: 16) {
            Text("💚")
                .font(.system(size: 64))
            Text("Alex")
                .font(.largeTitle.bold())
                .foregroundStyle(FondColors.text)
            Text("Available")
                .font(.title3)
                .foregroundStyle(FondColors.textSecondary)
        }
        .padding(32)
        .fondCard()
    }
}
