import Foundation
import SwiftUI

enum Format {
    /// "in 2h 41m" / "now" — the reset countdown, which is the number people actually plan around.
    static func countdown(to date: Date, from now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "now" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let leftover = hours % 24
            return leftover == 0 ? "in \(days)d" : "in \(days)d \(leftover)h"
        }
        if hours == 0 { return "in \(minutes)m" }
        return "in \(hours)h \(minutes)m"
    }

    /// "just now" / "4m ago" — how old a reading is.
    static func age(of date: Date, from now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 45 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// Green while there is room, amber when it is getting close, red when it is nearly gone.
    static func tint(forRemaining remaining: Double) -> Color {
        if remaining <= 10 { return .red }
        if remaining <= 25 { return .orange }
        return .green
    }
}
