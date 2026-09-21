import Foundation

/// Anything that can report quota for one coding agent.
///
/// Every provider is expected to try its best source first and fall back to weaker ones,
/// and to return `.unavailable` with a plain reason when nothing works. A provider must
/// never invent a number: an empty gauge is useful, a wrong one is not.
protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func read() async -> ProviderState
}

extension UsageProvider {
    /// Shared installation check: the provider's CLI on the user's real PATH.
    func installedBinaryPath() -> String? {
        ShellEnvironment.shared.locate(id.binaryName)
    }
}
