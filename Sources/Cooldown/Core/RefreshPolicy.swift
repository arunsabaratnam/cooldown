import Foundation

/// Decides when to read the quota next, so that nobody has to ask for it.
///
/// The app reads on launch, whenever the panel is opened, whenever the Mac wakes, after
/// a prepare run, and otherwise on the cadence below. The cadence tightens as a window
/// approaches its reset, because that is the moment the numbers actually move, and
/// relaxes the rest of the time, because every read spawns a process or two.
enum RefreshPolicy {
    /// While the panel is open, so the countdown in front of you stays honest.
    static let whileOpen: TimeInterval = 30
    /// The quiet background cadence.
    static let whileIdle: TimeInterval = 300
    /// Used around a reset, in both directions.
    static let nearReset: TimeInterval = 60
    /// How close to a reset counts as near.
    static let resetLeadIn: TimeInterval = 600
    /// A read landing exactly on a reset can still see the old window, so aim just past it.
    static let resetOvershoot: TimeInterval = 5
    /// How long after a reset we keep checking often. This is also what stops a provider
    /// that reports a reset time stuck in the past from spinning us in a tight loop.
    static let staleResetGrace: TimeInterval = 120
    /// Opening the panel does not re-read if the last read is younger than this.
    static let freshEnough: TimeInterval = 15
    /// Never schedule anything tighter than this.
    static let floor: TimeInterval = 10

    /// - Parameter resets: every window's reset time, from every provider on show.
    static func delay(isPanelOpen: Bool, resets: [Date], now: Date = Date()) -> TimeInterval {
        var delay = isPanelOpen ? whileOpen : whileIdle

        let justTurnedOver = resets.contains { reset in
            let age = now.timeIntervalSince(reset)
            return age >= 0 && age < staleResetGrace
        }
        if justTurnedOver {
            delay = min(delay, nearReset)
        }

        if let next = resets.filter({ $0 > now }).min() {
            let untilReset = next.timeIntervalSince(now)
            if untilReset < resetLeadIn {
                delay = min(delay, nearReset)
            }
            // Land the next read just after the window resets, rather than well past it.
            delay = min(delay, untilReset + resetOvershoot)
        }

        return max(floor, delay)
    }
}
