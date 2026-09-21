import Foundation

/// Both quota sources here are undocumented or only semi-documented, and the field
/// spellings differ between them and have changed over time (`resets_at` vs `resetsAt`
/// vs `reset_at`, seconds vs milliseconds, absolute vs relative). So we dig through
/// the parsed JSON by hand and accept every spelling we have seen, rather than binding
/// a `Codable` struct that breaks the moment a key is renamed.
enum JSONDig {
    static func object(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func child(_ dictionary: [String: Any]?, _ keys: [String]) -> [String: Any]? {
        guard let dictionary else { return nil }
        for key in keys {
            if let found = dictionary[key] as? [String: Any] { return found }
        }
        return nil
    }

    static func number(_ dictionary: [String: Any]?, _ keys: [String]) -> Double? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? Double { return value }
            if let value = dictionary[key] as? Int { return Double(value) }
            if let value = dictionary[key] as? NSNumber { return value.doubleValue }
            if let text = dictionary[key] as? String, let value = Double(text) { return value }
        }
        return nil
    }

    /// Accepts epoch seconds, epoch milliseconds, or an ISO-8601 string.
    static func date(_ dictionary: [String: Any]?, _ keys: [String]) -> Date? {
        guard let dictionary else { return nil }
        for key in keys {
            if let text = dictionary[key] as? String {
                if let parsed = isoDate(text) { return parsed }
                if let seconds = Double(text) { return epochDate(seconds) }
                continue
            }
            if let seconds = number(dictionary, [key]) { return epochDate(seconds) }
        }
        return nil
    }

    static func epochDate(_ value: Double) -> Date? {
        guard value > 0 else { return nil }
        // Anything this large is milliseconds, not seconds.
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func isoDate(_ text: String) -> Date? {
        isoWithFraction.date(from: text) ?? isoPlain.date(from: text)
    }

    /// A reading plus the key it came from, because the key decides how to read it.
    struct Reading {
        let value: Double
        let key: String
    }

    /// Like `number`, but says which spelling matched.
    static func reading(_ dictionary: [String: Any]?, _ keys: [String]) -> Reading? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = number(dictionary, [key]) { return Reading(value: value, key: key) }
        }
        return nil
    }

    /// Keys ending in `percent`/`percentage` are unambiguous: 0...100. `utilization` is
    /// not documented either way, so a set of utilisation readings that all sit at or
    /// below 1.0 is read as fractions and scaled up.
    ///
    /// The narrow ambiguity left is a `utilization` that really is a percentage and
    /// happens to be 1 or below, which would read as 100%. `scripts/probe.sh` prints the
    /// raw payload, so the scale can be pinned down on a real account and hard-coded.
    static func normalisePercentages(_ readings: [Reading]) -> [Double] {
        let ambiguousKeys: Set<String> = ["utilization", "utilisation"]
        let allAmbiguous = readings.allSatisfy { ambiguousKeys.contains($0.key) }
        let highest = readings.map(\.value).max() ?? 0
        let looksFractional = allAmbiguous && highest <= 1.0
        return readings.map { looksFractional ? $0.value * 100 : $0.value }
    }
}
