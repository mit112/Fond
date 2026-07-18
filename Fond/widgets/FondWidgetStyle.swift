import SwiftUI
import WidgetKit

struct FondWidgetStyle {
    let renderingMode: WidgetRenderingMode

    var primary: Color {
        renderingMode == .fullColor ? FondColors.ink : .primary
    }

    var secondary: Color {
        renderingMode == .fullColor ? FondColors.inkSecondary : .secondary
    }

    var background: Color {
        renderingMode == .fullColor ? FondColors.keepsake : .clear
    }

    var showsAuthoredEdge: Bool {
        renderingMode == .fullColor
    }
}

struct WidgetStatusDot: View {
    let status: UserStatus?
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(status?.statusColor ?? FondColors.inkSecondary)
            .frame(width: size, height: size)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

struct WidgetKeepsakeBackground: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let style = FondWidgetStyle(renderingMode: renderingMode)
        style.background
            .overlay {
                if style.showsAuthoredEdge && !isLuminanceReduced {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(FondColors.amber, lineWidth: 1)
                        .padding(1)
                }
            }
    }
}

enum FondWidgetType {
    static func name(size: CGFloat) -> Font {
        FondVariableFont.make(
            name: "Fraunces",
            size: size,
            relativeTo: .title,
            axes: ["opsz": 48, "SOFT": 28, "WONK": 1, "wght": 540]
        )
    }

    static func value(size: CGFloat) -> Font {
        FondVariableFont.make(
            name: "Fraunces",
            size: size,
            relativeTo: .title,
            axes: ["opsz": 56, "SOFT": 24, "WONK": 1, "wght": 560]
        )
    }

    static func voice(size: CGFloat = 16) -> Font {
        FondVariableFont.make(
            name: "Newsreader",
            size: size,
            relativeTo: .body,
            axes: ["opsz": 20, "wght": 400]
        )
    }
}

extension Date {
    func widgetFreshness(relativeTo now: Date = .now) -> String {
        let interval = max(0, now.timeIntervalSince(self))
        if interval < 60 { return "now" }
        if interval < 3_600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3_600))h" }
        return "\(Int(interval / 86_400))d"
    }
}

struct WidgetVoiceRule: View {
    var body: some View {
        Rectangle()
            .fill(FondColors.amber)
            .frame(width: 1)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}
