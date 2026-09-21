import SwiftUI

struct SettingsSection: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(ProviderID.allCases) { provider in
                    Toggle(provider.displayName, isOn: binding(for: provider))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                }
            }

            Picker("Menu bar", selection: $store.settings.menuBarDisplay) {
                ForEach(MenuBarDisplay.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .font(.system(size: 11))

            Toggle("Show what is left, not what is used", isOn: $store.settings.showRemaining)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            VStack(alignment: .leading, spacing: 6) {
                Text("Prepare commands")
                    .font(.system(size: 11))
                ForEach(ProviderID.allCases) { provider in
                    TextField(provider.displayName, text: commandBinding(for: provider))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
                Text("Run in your login shell. Keep them short — they spend quota.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func binding(for provider: ProviderID) -> Binding<Bool> {
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

    private func commandBinding(for provider: ProviderID) -> Binding<String> {
        Binding(
            get: { store.settings.prepareCommand(for: provider) },
            set: { store.settings.prepareCommands[provider] = $0 }
        )
    }
}
