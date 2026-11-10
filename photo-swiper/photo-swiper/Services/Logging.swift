import OSLog

extension Logger {
    /// Every log line's subsystem, so `log stream --predicate 'subsystem == "…"'` sees them all.
    static let appSubsystem = "com.israelavendanojr.photo-swiper"

    /// A logger for one part of the app, e.g. "feed" or "index".
    static func app(category: String) -> Logger {
        Logger(subsystem: appSubsystem, category: category)
    }
}
