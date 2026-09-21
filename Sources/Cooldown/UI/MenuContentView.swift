import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: UsageStore
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(store.visibleProviders) { provider in
                        ProviderSection(provider: provider, store: store)
                    }
                    if store.visibleProviders.isEmpty {
                        NoDataRow(message: "No providers are switched on. Open settings below to pick some.")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 360)

            Divider()
            prepareSection
            Divider()
            footer

            if showingSettings {
                Divider()
                SettingsSection(store: store)
            }
        }
        .frame(width: 300)
        .onAppear { store.panelAppeared() }
        .onDisappear { store.panelDisappeared() }
    }

    private var header: some View {
        HStack {
            Text("Usage")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            // No refresh button: the app reads on its own, and this line is only here
            // so you can tell at a glance how current the numbers are.
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else if let lastRefresh = store.lastRefresh {
                Text("Updated \(Format.age(of: lastRefresh))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var prepareSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                store.prepareAll()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(store.preparing.isEmpty ? "Start the 5-hour cooldown" : "Starting…")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(!store.preparing.isEmpty || store.visibleProviders.isEmpty)

            Text("Sends one short throwaway prompt now, so the 5-hour clock is already running when you sit down. It shifts the window earlier; it does not add quota, and it does not move the weekly window.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(store.recentOutcomes) { outcome in
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(outcome.succeeded ? Color.green : Color.orange)
                    Text("\(outcome.provider.displayName): \(outcome.succeeded ? "started \(Format.age(of: outcome.at))" : outcome.detail)")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Button(showingSettings ? "Hide settings" : "Settings") {
                showingSettings.toggle()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct ProviderSection: View {
    let provider: ProviderID
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let snapshot = state.snapshot {
                    Text(Format.age(of: snapshot.capturedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            switch state {
            case .ok(let snapshot):
                ForEach(snapshot.sortedWindows) { window in
                    WindowRow(window: window, showRemaining: store.settings.showRemaining)
                }
                Text(snapshot.source)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            case .notInstalled:
                NoDataRow(message: "\(provider.binaryName) is not on your PATH, so there is nothing to read.")
            case .neverRead:
                NoDataRow(message: "Not read yet.")
            case .unavailable(let reason):
                NoDataRow(message: "No quota available — \(reason).")
            }
        }
    }

    private var state: ProviderState {
        store.states[provider] ?? .neverRead
    }
}
