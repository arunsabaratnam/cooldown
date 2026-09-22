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

    /// "11:42 PM", in the user's own clock style.
    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Thu 9:00 AM" for anything past today, "11:42 PM" for today.
    static func resetMoment(_ date: Date, now: Date = Date()) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) { return clockTime(date) }
        let day = date.formatted(.dateTime.weekday(.abbreviated))
        return "\(day) \(clockTime(date))"
    }

    /// "3h 12m", without the "in", for when the sentence supplies its own.
    static func duration(until date: Date, from now: Date = Date()) -> String {
        let text = countdown(to: date, from: now)
        return text.hasPrefix("in ") ? String(text.dropFirst(3)) : text
    }
}
