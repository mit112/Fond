//
//  Date+Extensions.swift
//  Fond
//
//  Date formatting helpers for widget display and history feed.
//

import Foundation

extension Date {
    /// "2m ago", "1h ago", "3d ago" — compact relative time for widgets.
    var shortTimeAgo: String {
        let interval = Date().timeIntervalSince(self)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if hours < 24 { return "\(hours)h ago" }
        return "\(days)d ago"
    }

    /// "Today 3:42 PM" or "Feb 14 3:42 PM" — for history feed.
    var historyTimestamp: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(self) {
            formatter.dateFormat = "'Today' h:mm a"
        } else if calendar.isDateInYesterday(self) {
            formatter.dateFormat = "'Yesterday' h:mm a"
        } else {
            formatter.dateFormat = "MMM d h:mm a"
        }

        return formatter.string(from: self)
    }
}
