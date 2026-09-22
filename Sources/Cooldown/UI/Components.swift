import SwiftUI

/// The 270° ring used everywhere: the menu bar icon, the app icon and the panel. It
/// starts bottom-left and fills clockwise, with the gap at the bottom.
struct GaugeRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 4
    var tint: Color
    var track: Color

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: 0.75 * min(1, max(0, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .rotationEffect(.degrees(135))
        .padding(lineWidth / 2)
    }
}

struct MeterBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 6
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(fraction > 0 ? height : 0, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

/// A logo path from `LogoPaths`, scaled to whatever frame it is given.
struct LogoShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return path
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: rect.minX + (rect.width - 24 * scale) / 2, dy: rect.minY + (rect.height - 24 * scale) / 2)
    }
}

/// The mark for each account: Claude's spark, OpenAI's for Codex, and the same mark
/// white-on-black for ChatGPT so the two OpenAI rows can be told apart.
struct AccountLogo: View {
    let account: AccountID
    var size: CGFloat = 18
    @Environment(\.theme) private var theme

    var body: some View {
        switch account {
        case .claude:
            LogoShape(path: LogoPaths.claude)
                .fill(Color(hex: 0xD97757))
                .frame(width: size, height: size)
        case .codex:
            LogoShape(path: LogoPaths.openAI)
                .fill(theme.text)
                .frame(width: size, height: size)
        case .chatgpt:
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Color.black)
                .frame(width: size, height: size)
                .overlay(
                    LogoShape(path: LogoPaths.openAI)
                        .fill(Color.white)
                        .frame(width: size * 0.62, height: size * 0.62)
                )
        }
    }
}

extension ProviderID {
    var account: AccountID {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        }
    }
}

/// Says plainly why there is no number, instead of showing a zero that looks like data.
struct NoDataRow: View {
    let message: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Running low", in the same amber whatever the theme.
struct LowBadge: View {
    var body: some View {
        Text("Running low")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.warningText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.warningFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
