import SwiftUI

/// One quota window: what it is, how much is left, and when it comes back.
struct WindowRow: View {
    let window: UsageWindow
    let showRemaining: Bool

    private var displayedPercent: Double {
        showRemaining ? window.remainingPercent : window.usedPercent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.kind.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Format.percent(displayedPercent))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                Text(showRemaining ? "left" : "used")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            MeterBar(
                fraction: min(1, max(0, window.remainingPercent / 100)),
                tint: Format.tint(forRemaining: window.remainingPercent)
            )

            if let resetsAt = window.resetsAt {
                Text("resets \(Format.countdown(to: resetsAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct MeterBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.09))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint)
                    .frame(width: max(2, geometry.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}

/// Says plainly why there is no number, instead of showing a zero that looks like data.
struct NoDataRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
