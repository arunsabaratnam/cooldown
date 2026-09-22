import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, accounts, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .accounts: return "Accounts"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintpalette"
        case .accounts: return "person.crop.circle"
        case .about: return "info.circle"
        }
    }
}

struct SettingsWindow: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    /// Settings keeps the system's own colours; the theme only supplies the accent, and
    /// the logos' ink, so they stay visible in dark mode.
    private var theme: Theme { store.settings.activeTheme(systemIsDark: colorScheme == .dark) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(store.settingsPane.title)
                        .font(.system(size: 20, weight: .bold))
                    switch store.settingsPane {
                    case .general: GeneralPane(store: store)
                    case .appearance: AppearancePane(store: store)
                    case .accounts: AccountsPane(store: store)
                    case .about: AboutPane()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 760, height: 600)
        .tint(theme.button)
        .environment(\.theme, theme)
        .onAppear { store.refreshAccounts(force: true) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsPane.allCases) { pane in
                let selected = store.settingsPane == pane
                Button {
                    store.settingsPane = pane
                } label: {
                    Label(pane.title, systemImage: pane.symbol)
                        .font(.system(size: 13, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(
                            selected ? theme.button : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 16)
        .frame(width: 200)
        .background(SidebarMaterial())
    }
}

// MARK: - Building blocks

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// A white rounded group of rows, like System Settings.
private struct SettingsGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            VStack(spacing: 0) { content }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}

private struct Row<Trailing: View>: View {
    let title: String
    var caption: String? = nil
    var showsDivider = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    if let caption {
                        Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if showsDivider {
                Divider().padding(.leading, 14)
            }
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "Menu bar") {
                Row(title: "Icon") {
                    Picker("Icon", selection: $store.settings.menuBarIcon) {
                        ForEach(MenuBarIcon.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Row(title: "Show percentage next to icon", caption: "Off keeps the menu bar to one small icon.", showsDivider: false) {
                    Toggle("", isOn: $store.settings.showPercentInMenuBar).toggleStyle(.switch).labelsHidden()
                }
            }

            SettingsGroup(title: "Panel") {
                Row(title: "Show what’s left, not what’s used") {
                    Toggle("", isOn: $store.settings.showRemaining).toggleStyle(.switch).labelsHidden()
                }
                Row(title: "Mark as running low below", showsDivider: false) {
                    Picker("", selection: $store.settings.lowThreshold) {
                        ForEach(Settings.lowThresholdChoices, id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsGroup(title: "Cooldown") {
                Row(title: "Notify me when a window resets") {
                    Toggle("", isOn: $store.settings.notifyOnReset).toggleStyle(.switch).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start commands").font(.system(size: 13))
                    ForEach(ProviderID.allCases) { provider in
                        HStack(spacing: 10) {
                            Text(provider.displayName)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .leading)
                            TextField(provider.displayName, text: commandBinding(for: provider))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .labelsHidden()
                        }
                    }
                    Text("Run in your login shell. Keep them short, they spend quota.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            SettingsGroup(title: "Startup") {
                Row(title: "Open at login", showsDivider: false) {
                    Toggle("", isOn: $store.settings.launchAtLogin).toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }

    private func commandBinding(for provider: ProviderID) -> Binding<String> {
        Binding(
            get: { store.settings.prepareCommand(for: provider) },
            set: { store.settings.prepareCommands[provider] = $0 }
        )
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Theme")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                    ForEach(ThemeID.allCases) { id in
                        ThemeTile(theme: id.theme, selected: store.settings.theme == id) {
                            store.settings.theme = id
                        }
                    }
                }
            }

            SettingsGroup(title: nil) {
                Row(title: "Follow macOS dark mode", caption: "Switch theme when your Mac goes dark.") {
                    Picker("", selection: $store.settings.darkTheme) {
                        ForEach(ThemeID.allCases) { Text($0.theme.name).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!store.settings.followSystemDarkMode)
                    Toggle("", isOn: $store.settings.followSystemDarkMode).toggleStyle(.switch).labelsHidden()
                }
                Row(title: "Tint the menu bar ring", caption: "Colour the icon with the theme instead of plain white.", showsDivider: false) {
                    Toggle("", isOn: $store.settings.tintMenuBarIcon).toggleStyle(.switch).labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Panel layout")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(PanelLayout.allCases) { layout in
                        LayoutTile(layout: layout, selected: store.settings.panelLayout == layout) {
                            store.settings.panelLayout = layout
                        }
                    }
                }
            }

            SettingsGroup(title: nil) {
                Row(title: "Density", showsDivider: false) {
                    Picker("", selection: $store.settings.density) {
                        ForEach(Density.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}

private struct ThemeTile: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    GaugeRing(fraction: 0.7, lineWidth: 3.5, tint: theme.accent, track: theme.track)
                        .frame(width: 30, height: 30)
                    VStack(spacing: 5) {
                        MeterBar(fraction: 0.7, tint: theme.accent, height: 4)
                            .environment(\.theme, theme)
                        RoundedRectangle(cornerRadius: 4).fill(theme.card).frame(height: 12)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 64)
                .background(theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.black.opacity(0.1)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? theme.button : Color.clear, lineWidth: 2)
                        .padding(-4)
                )
                Text(theme.name)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LayoutTile: View {
    let layout: PanelLayout
    let selected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(layout.label).font(.system(size: 12, weight: .semibold))
                Text(layout.blurb)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? theme.button : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var preview: some View {
        switch layout {
        case .rings:
            HStack(spacing: 10) {
                GaugeRing(fraction: 0.82, lineWidth: 4, tint: theme.accent, track: theme.track).frame(width: 30, height: 30)
                GaugeRing(fraction: 0.64, lineWidth: 3, tint: theme.accent, track: theme.track).frame(width: 20, height: 20)
            }
        case .classic:
            VStack(spacing: 9) {
                MeterBar(fraction: 0.82, tint: theme.accent, height: 5)
                MeterBar(fraction: 0.54, tint: theme.accent, height: 5)
            }
            .frame(width: 60)
        }
    }
}

// MARK: - Accounts

private struct AccountsPane: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in once and Cooldown keeps reading your limits on its own.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, -12)
            ForEach(AccountID.allCases) { account in
                SettingsGroup(title: nil) {
                    AccountRow(account: account, store: store, logoSize: 28)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    if store.accounts[account]?.isSignedIn == true {
                        let provider = account.provider
                        Divider().padding(.leading, 58)
                        HStack {
                            Text("Show in panel and menu bar").font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: enabledBinding(provider)).toggleStyle(.switch).labelsHidden()
                        }
                        .padding(.leading, 58)
                        .padding(.trailing, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func enabledBinding(_ provider: ProviderID) -> Binding<Bool> {
        Binding(
            get: { store.settings.enabledProviders.contains(provider) },
            set: { isOn in
                if isOn {
                    store.settings.enabledProviders.insert(provider)
                } else {
                    store.settings.enabledProviders.remove(provider)
                }
            }
        )
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text("Cooldown").font(.system(size: 17, weight: .semibold))
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("See how much Claude and Codex you have left, and start the 5-hour cooldown before you sit down to work.")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
}
