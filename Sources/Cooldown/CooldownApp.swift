import SwiftUI

@main
@MainActor
struct CooldownApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
            if !store.menuBarTitle.isEmpty {
                Text(store.menuBarTitle)
                    .monospacedDigit()
            }
        }
    }

    /// A rough battery-style read on the tightest 5-hour window, so the icon alone
    /// says something even before you read the number.
    private var symbolName: String {
        let remaining = store.visibleProviders
            .compactMap { store.states[$0]?.snapshot?.window(.fiveHour)?.remainingPercent }
            .min()
        guard let remaining else { return "gauge.with.dots.needle.bottom.50percent" }
        if remaining <= 10 { return "gauge.with.dots.needle.bottom.0percent" }
        if remaining <= 40 { return "gauge.with.dots.needle.bottom.50percent" }
        return "gauge.with.dots.needle.bottom.100percent"
    }
}
