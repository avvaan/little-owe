import Foundation

/// The window reflects the device clock. Four buckets rather than the three named in
/// the brief: "evening" and "night" look very different through a round window, and a
/// child playing at 21:30 should see the moon high, not a sunset.
enum TimeOfDay: String, CaseIterable {
    case morning
    case day
    case evening
    case night

    static func current(date: Date = Date(), calendar: Calendar = .current) -> TimeOfDay {
        switch calendar.component(.hour, from: date) {
        case 5..<11:  return .morning
        case 11..<17: return .day
        case 17..<21: return .evening
        default:      return .night
        }
    }
}

/// Polls the clock from the scene's update loop — no timers, so nothing fires while
/// the app is backgrounded and there is no lifecycle bookkeeping to get wrong.
struct TimeOfDayWatcher {

    private(set) var current: TimeOfDay
    private var lastCheck: TimeInterval = 0
    private let interval: TimeInterval

    /// A minute is plenty: the only visible jump is at a bucket boundary.
    init(interval: TimeInterval = 60, now: Date = Date()) {
        self.interval = interval
        self.current = TimeOfDay.current(date: now)
    }

    /// Returns the new value only when the bucket actually changed.
    mutating func poll(sceneTime: TimeInterval, now: Date = Date()) -> TimeOfDay? {
        guard sceneTime - lastCheck >= interval || lastCheck == 0 else { return nil }
        lastCheck = sceneTime
        let fresh = TimeOfDay.current(date: now)
        guard fresh != current else { return nil }
        current = fresh
        return fresh
    }

    /// Called when the app comes back to the foreground, where a long gap may have passed.
    mutating func refresh(now: Date = Date()) -> TimeOfDay? {
        let fresh = TimeOfDay.current(date: now)
        guard fresh != current else { return nil }
        current = fresh
        return fresh
    }
}
