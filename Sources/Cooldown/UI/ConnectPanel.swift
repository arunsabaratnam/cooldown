import SwiftUI

/// What the panel shows before anything can be read: one Connect button per account.
struct ConnectPanel: View {
    @ObservedObject var store: UsageStore
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cooldown reads usage from the accounts you already use. Pick the ones you want to keep an eye on.")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(AccountID.allCases.enumerated()), id: \.element) { index, account in
                    if index > 0 {
                        Rectangle().fill(theme.track).frame(height: 1).padding(.horizontal, 12)
                    }
                    AccountRow(account: account, store: store, logoSize: 26)
                        .padding(12)
                }
            }
            .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("You can change this any time in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Logo, name, the signed-in email and plan when there is one, and one button.
/// Shared by the first-run panel and Settings → Accounts.
struct AccountRow: View {
    let account: AccountID
    @ObservedObject var store: UsageStore
    var logoSize: CGFloat = 28
    @Environment(\.theme) private var theme

    private var state: AccountState { store.accounts[account] ?? .unknown }

    var body: some View {
        HStack(spacing: 12) {
            AccountLogo(account: account, size: logoSize)
                .frame(width: logoSize + 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 13, weight: .semibold))
                if case .signedIn(let info) = state, let summary = info.summary {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondary)
                }
            }
            Spacer()
            button
        }
    }

    @ViewBuilder
    private var button: some View {
        switch state {
        case .signedIn:
            Button("Sign out") { store.signOut(account) }
                .controlSize(.regular)
        case .notInstalled:
            Button("Connect") {}
                .buttonStyle(.borderedProminent)
                .disabled(true)
                .help("Install the \(account.binaryName) command-line tool first.")
        case .signedOut, .unknown:
            Button("Connect") { store.connect(account) }
                .buttonStyle(.borderedProminent)
                .tint(theme.button)
        }
    }
}
