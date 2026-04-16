import Foundation

public enum ResetDuration {
    public static func string(from date: Date, now: Date = Date()) -> String {
        let interval = max(0, date.timeIntervalSince(now))
        let totalSeconds = Int(interval)
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        if days > 0 { return String(localized: "time.daysHours \(days) \(hours)", bundle: .module) }
        return String(localized: "time.hoursMinutes \(hours) \(minutes)", bundle: .module)
    }
}
