import SwiftUI

/// The Classic layout: a card of bars for each provider.
struct ClassicPanel: View {
    @ObservedObject var store: UsageStore
    let now: Date
    @Environment(\.density) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 10 : 14) {
            ForEach(store.visibleProviders) { provider in
                ProviderCard(provider: provider, store: store, now: now)
            }
        }
    }
}

private struct ProviderCard: View {
    let provider: ProviderID
    @ObservedObject var store: UsageStore
    let now: Date
    @Environment(\.theme) private var theme
    @Environment(\.density) private var density

    private var plan: String? {
        if case .signedIn(let info) = store.accounts[provider.account] { return info.plan }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AccountLogo(account: provider.account, size: 18)
                Text(provider.displayName)
                    .font(.system(size: 15, weight: .semibold))
                if let plan {
                    Text(plan)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: density == .compact ? 10 : 16) {
                switch store.states[provider] ?? .neverRead {
                case .ok(let snapshot):
                    ForEach(snapshot.sortedWindows) { window in
                        WindowRow(window: window, store: store, now: now)
                    }
                case .notInstalled:
                    NoDataRow(message: "\(provider.binaryName) isn’t installed, so there’s nothing to read.")
                case .neverRead:
                    NoDataRow(message: "Not read yet.")
                case .unavailable(let reason):
                    NoDataRow(message: "No numbers right now: \(reason).")
                }
            }
            .padding(density == .compact ? 10 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// One quota window: what it is, how much is left, and when it comes back.
private struct WindowRow: View {
    let window: UsageWindow
    @ObservedObject var store: UsageStore
    let now: Date
    @Environment(\.theme) private var theme

    var body: some View {
        let remaining = window.remainingPercent
        let low = remaining <= Double(store.settings.lowThreshold)
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(window.kind.label)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if low { LowBadge() }
            }
            MeterBar(
                fraction: remaining / 100,
                tint: theme.tint(forRemaining: remaining, lowThreshold: store.settings.lowThreshold)
            )
            HStack {
                Text(store.settings.showRemaining
                     ? "\(Format.percent(remaining)) left"
                     : "\(Format.percent(window.usedPercent)) used")
                    .monospacedDigit()
                Spacer()
                Text(resetText)
                    .foregroundStyle(theme.secondary)
            }
            .font(.system(size: 12))
        }
    }

    private var resetText: String {
        if window.kind == .fiveHour, window.isFull { return "Not started" }
        guard let resetsAt = window.resetsAt else { return "" }
        return window.kind == .fiveHour
            ? "Resets \(Format.countdown(to: resetsAt, from: now))"
            : "Resets \(Format.resetMoment(resetsAt, now: now))"
    }
}
