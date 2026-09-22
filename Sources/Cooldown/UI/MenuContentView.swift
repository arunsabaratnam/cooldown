import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme {
        store.settings.activeTheme(systemIsDark: colorScheme == .dark)
    }

    private var spacing: CGFloat { store.settings.density == .compact ? 10 : 14 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: spacing) {
                header
                content(now: context.date)
                if !showsConnect {
                    cooldownSection(now: context.date)
                }
                footer
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .frame(width: 352)
        .background(theme.background)
        .foregroundStyle(theme.text)
        .environment(\.theme, theme)
        .environment(\.density, store.settings.density)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .tint(theme.button)
        .onAppear { store.panelAppeared() }
        .onDisappear { store.panelDisappeared() }
    }

    /// Nothing on show could be read and nobody is signed in: offer the sign-ins
    /// instead of an empty panel.
    private var showsConnect: Bool {
        store.nothingConnected && !store.accounts.values.contains { $0.isSignedIn }
            && !store.isRefreshing && store.lastRefresh != nil
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if store.visibleProviders.isEmpty {
            NoDataRow(message: "No providers are switched on. Turn some on in Settings → Accounts.")
                .padding(.horizontal, 4)
        } else if showsConnect {
            ConnectPanel(store: store)
        } else {
            switch store.settings.panelLayout {
            case .rings: RingsPanel(store: store, now: now)
            case .classic: ClassicPanel(store: store, now: now)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(showsConnect ? "Connect your tools" : "Cooldown")
                .font(.system(size: showsConnect ? 17 : 15, weight: .semibold))
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            }
            SettingsMenuButton(store: store, open: openPane)
        }
        .padding(.horizontal, 4)
    }

    private func cooldownSection(now: Date) -> some View {
        VStack(spacing: 7) {
            Button {
                store.prepareAll()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(store.prepareLabel)
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .foregroundStyle(store.canPrepare ? Color.white : theme.secondary)
                .background(
                    store.canPrepare ? theme.button : theme.card,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!store.canPrepare)
            .help("Sends one short throwaway prompt now, so the 5-hour clock is already running when you sit down. It shifts the window earlier; it does not add quota.")

            Text(store.prepareNote(now: now))
                .font(.system(size: 11))
                .foregroundStyle(theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            ForEach(store.recentOutcomes.filter { !$0.succeeded }) { outcome in
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                    Text("\(outcome.provider.displayName) didn’t start: \(outcome.detail)")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 10))
                .foregroundStyle(theme.secondary)
            }
        }
        .padding(.top, 2)
    }

    private var footer: some View {
        HStack {
            if let lastRefresh = store.lastRefresh {
                Text("Updated \(Format.age(of: lastRefresh))")
            } else {
                Text("Reading…")
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.track.opacity(0.7)).frame(height: 1)
        }
    }

    private func openPane(_ pane: SettingsPane) {
        SettingsWindowController.shared.show(pane, store: store)
    }
}

/// The gear in the header: grey at rest, a soft fill on hover, and a short menu.
struct SettingsMenuButton: View {
    @ObservedObject var store: UsageStore
    let open: (SettingsPane) -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Menu {
            Button("Settings…") { open(.general) }
                .keyboardShortcut(",", modifiers: .command)
            Button("Accounts…") { open(.accounts) }
            Divider()
            Button("About Cooldown") { open(.about) }
            Button("Quit Cooldown") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(hovering ? theme.text : theme.secondary)
                .frame(width: 28, height: 28)
                .background(
                    hovering ? theme.track.opacity(0.8) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(hovering ? theme.text : theme.secondary)
        .fixedSize()
        .onHover { hovering = $0 }
        .accessibilityLabel("Settings")
    }
}
