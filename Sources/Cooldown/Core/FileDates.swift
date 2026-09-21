import Foundation

enum FileDates {
    /// `URLResourceValues.contentModificationDate` is itself optional, so reading it
    /// through `try?` gives a doubly-optional value. Flatten it once, here.
    static func modified(_ url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }
}
