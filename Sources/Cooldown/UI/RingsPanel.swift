import SwiftUI

/// The Rings layout: the window closest to running out as one big ring, today's 5-hour
/// windows on a timeline, then everything else in a short list.
struct RingsPanel: View {
    @ObservedObject var store: UsageStore
    let now: Date
    @Environment(\.theme) private var theme
    @Environment(\.density) private var density

    private struct Entry: Identifiable {
        let provider: ProviderID
        let window: UsageWindow
        var id: String { "\(provider.rawValue).\(window.kind.rawValue)" }
    }

    private var spacing: CGFloat { density == .compact ? 8 : 12 }

    /// The 5-hour window with the least left. A full window only leads when every one is full.
    private var hero: Entry? {
        store.visibleProviders
            .compactMap { provider in
                store.states[provider]?.snapshot?.window(.fiveHour).map { Entry(provider: provider, window: $0) }
            }
            .min { $0.window.remainingPercent < $1.window.remainingPercent }
    }

    private var others: [Entry] {
        store.visibleProviders.flatMap { provider -> [Entry] in
            guard let snapshot = store.states[provider]?.snapshot else { return [] }
            return snapshot.sortedWindows
                .filter { !($0.kind == hero?.window.kind && provider == hero?.provider) }
                .map { Entry(provider: provider, window: $0) }
        }
    }

    /// One line per provider that has no numbers, or whose numbers are older than they look.
    private var notes: [(ProviderID, String)] {
        store.visibleProviders.compactMap { provider in
            switch store.states[provider] ?? .neverRead {
            case .ok: return store.staleNote(for: provider, now: now).map { (provider, $0) }
            case .neverRead: return (provider, "Not read yet.")
            case .notInstalled: return (provider, "\(provider.binaryName) isn’t installed, so there’s nothing to read.")
            case .unavailable(let reason, _): return (provider, "No numbers right now: \(reason).")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let hero {
                heroCard(hero)
                timeline
            }
            if !others.isEmpty || !notes.isEmpty {
                list
            }
        }
    }

    // MARK: - Hero

    private func heroCard(_ entry: Entry) -> some View {
        let remaining = entry.window.remainingPercent
        let size: CGFloat = density == .compact ? 92 : 112
        return HStack(spacing: 16) {
            ZStack {
                GaugeRing(
                    fraction: remaining / 100,
                    lineWidth: size * 0.09,
                    tint: theme.tint(forRemaining: remaining, lowThreshold: store.settings.lowThreshold),
                    track: theme.track
                )
                VStack(spacing: 2) {
                    Text(percentText(entry.window))
                        .font(.system(size: size * (percentText(entry.window).count > 3 ? 0.22 : 0.27), weight: .bold))
                        .monospacedDigit()
                    Text(store.settings.showRemaining ? "left" : "used")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.heroText)
                }
            }
            .frame(width: size, height: size)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    AccountLogo(account: entry.provider.account, size: 16)
                    Text("\(entry.provider.displayName) · 5-hour")
                        .font(.system(size: 13, weight: .semibold))
                }
                if let resetsAt = entry.window.resetsAt, !entry.window.isFull {
                    Text(Format.duration(until: resetsAt, from: now))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                    Text("until it resets at \(Format.clockTime(resetsAt))")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.heroText)
                } else {
                    Text("Full")
                        .font(.system(size: 22, weight: .bold))
                    Text("Not started yet")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.heroText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(density == .compact ? 12 : 16)
        .background(theme.hero, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Timeline

    private var timeline: some View {
        let rows = store.visibleProviders.compactMap { provider -> (ProviderID, UsageWindow)? in
            store.states[provider]?.snapshot?.window(.fiveHour).map { (provider, $0) }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("TODAY’S 5-HOUR WINDOWS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(theme.secondary)
            ForEach(rows, id: \.0) { provider, window in
                timelineRow(provider, window)
            }
        }
        .padding(.horizontal, 4)
    }

    private func timelineRow(_ provider: ProviderID, _ window: UsageWindow) -> some View {
        let running = !window.isFull && window.startedAt != nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(provider.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                if running, let start = window.startedAt, let end = window.resetsAt {
                    Text("\(Format.clockTime(start)) → \(Format.clockTime(end))")
                } else {
                    Text("Starts when you do · would end \(Format.clockTime(now.addingTimeInterval(5 * 3600)))")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(theme.secondary)

            if running, let start = window.startedAt, let end = window.resetsAt {
                let elapsed = min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.track).frame(height: 8)
                        Capsule().fill(theme.accent).frame(width: max(8, geometry.size.width * elapsed), height: 8)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(theme.text)
                            .frame(width: 3, height: 14)
                            .offset(x: min(geometry.size.width - 3, max(0, geometry.size.width * elapsed - 1.5)))
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 14)
                .accessibilityLabel("\(Int((elapsed * 100).rounded()))% of the way through")
            } else {
                Capsule()
                    .strokeBorder(theme.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(height: 8)
                    .padding(.vertical, 3)
            }
        }
    }

    // MARK: - The rest

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(others.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { divider }
                row(entry)
            }
            ForEach(notes, id: \.0) { provider, message in
                if !others.isEmpty || provider != notes.first?.0 { divider }
                HStack(alignment: .top, spacing: 10) {
                    AccountLogo(account: provider.account, size: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName).font(.system(size: 13, weight: .semibold))
                        NoDataRow(message: message)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(theme.track).frame(height: 1).padding(.horizontal, 4)
    }

    private func row(_ entry: Entry) -> some View {
        let remaining = entry.window.remainingPercent
        let low = remaining <= Double(store.settings.lowThreshold)
        return HStack(spacing: 10) {
            GaugeRing(
                fraction: remaining / 100,
                lineWidth: 3.5,
                tint: theme.tint(forRemaining: remaining, lowThreshold: store.settings.lowThreshold),
                track: theme.track
            )
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    AccountLogo(account: entry.provider.account, size: 16)
                    Text("\(entry.provider.displayName) \(entry.window.kind.label.lowercasedFirst)")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(subtitle(entry.window, low: low))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondary)
            }
            Spacer(minLength: 0)
            Text(percentText(entry.window))
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(low ? (theme.isDark ? Theme.warning : Theme.warningText) : theme.text)
        }
        .padding(.vertical, density == .compact ? 6 : 8)
        .padding(.horizontal, 4)
    }

    private func subtitle(_ window: UsageWindow, low: Bool) -> String {
        var text: String
        if window.kind == .fiveHour, window.isFull {
            text = "Not started"
        } else if let resetsAt = window.resetsAt {
            text = window.kind == .fiveHour
                ? "Resets \(Format.countdown(to: resetsAt, from: now))"
                : "Resets \(Format.resetMoment(resetsAt, now: now))"
        } else {
            text = "No reset time reported"
        }
        if low { text += " · running low" }
        return text
    }

    private func percentText(_ window: UsageWindow) -> String {
        Format.percent(store.settings.showRemaining ? window.remainingPercent : window.usedPercent)
    }
}

extension String {
    /// "Weekly" → "weekly", for "Claude weekly". Leaves "5-hour" alone.
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
