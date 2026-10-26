import Foundation

/// Display formatting shared by every screen.
enum Format {
    /// "3.4 MB", "38 MB", "1.23 GB".
    static func size(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 {
            let gb = mb / 1000
            return gb >= 10 ? String(format: "%.1f GB", gb) : String(format: "%.2f GB", gb)
        }
        return mb < 10 ? String(format: "%.1f MB", mb) : "\(Int(mb.rounded())) MB"
    }

    /// "Saturday, September 14".
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "Sep 14".
    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Sep 22 – 28", or "Sep 29 – Oct 3" across months.
    static func range(_ dates: [Date]) -> String {
        guard let from = dates.min(), let to = dates.max() else { return "" }
        let calendar = Calendar.current
        if calendar.isDate(from, inSameDayAs: to) { return shortDay(from) }
        if calendar.isDate(from, equalTo: to, toGranularity: .month) {
            return "\(shortDay(from)) – \(calendar.component(.day, from: to))"
        }
        return "\(shortDay(from)) – \(shortDay(to))"
    }

    /// "4:12".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "2h 14m", "14m", or "45s" under a minute. Counts down to a refill.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        if total < 60 { return "\(total)s" }
        let minutes = (total + 59) / 60
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    /// "about 3 weeks", "about 5 days", "about 2 months", for a long stretch of days.
    static func roughDays(_ days: Double) -> String {
        let d = Int(days.rounded(.up))
        if d < 14 { return "about \(d) days" }
        if d < 60 { return "about \(Int((days / 7).rounded())) weeks" }
        return "about \(Int((days / 30).rounded())) months"
    }

    /// "five", for small counts in copy.
    static func spelled(_ n: Int) -> String {
        n <= 10 ? (spellOut.string(from: n as NSNumber) ?? "\(n)") : "\(n)"
    }

    /// "17,820".
    static func count(_ n: Int) -> String {
        n.formatted(.number)
    }

    private static let spellOut: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        return f
    }()
}
