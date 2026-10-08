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
