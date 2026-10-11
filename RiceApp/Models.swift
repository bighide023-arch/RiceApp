import Foundation

/// data/prices.json の中身。キーは snake_case なので convertFromSnakeCase で読む。
struct PriceData: Codable {
    let retailWeekly: RetailWeekly
    let wholesaleMonthly: WholesaleMonthly?
    let updatedAt: String

    /// 数字が最後に変わった日時。読めなければ nil
    var updatedDate: Date? { ISO8601DateFormatter().date(from: updatedAt) }
}

/// スーパーでの販売価格（KSP-POS、全国、週次）
struct RetailWeekly: Codable {
    let unit: String
    let source: String
    let sourceUrl: String
    let published: String
    let weeks: [RetailWeek]
}

struct RetailWeek: Codable, Identifiable, Hashable {
    let weekStart: String
    let weekEnd: String
    /// 銘柄米
    let brand: Int
    /// その他（ブレンド米等）
    let blend: Int
    /// 全平均
    let average: Int

    var id: String { weekStart }
    var startDate: Date { DateParser.day(weekStart) }
    var endDate: Date { DateParser.day(weekEnd) }
}

/// 米の相対取引価格（月次、円/玄米60kg）
struct WholesaleMonthly: Codable {
    let unit: String
    let source: String
    let sourceUrl: String
    let average: [MonthPrice]
    let cropYear: Int
    let brands: [BrandPrice]
}

struct MonthPrice: Codable, Identifiable, Hashable {
    let month: String
    let price: Int

    var id: String { month }
    var date: Date { DateParser.month(month) }
}

struct BrandPrice: Codable, Identifiable, Hashable {
    let region: String
    let variety: String
    let prices: [String: Int]

    var id: String { region + variety }

    var sortedPrices: [MonthPrice] {
        prices.map { MonthPrice(month: $0.key, price: $0.value) }.sorted { $0.month < $1.month }
    }

    var latest: MonthPrice? { sortedPrices.last }
}

enum DateParser {
    private static let dayFormatter = makeFormatter("yyyy-MM-dd")
    private static let monthFormatter = makeFormatter("yyyy-MM")

    static func day(_ s: String) -> Date { dayFormatter.date(from: s) ?? .distantPast }
    static func month(_ s: String) -> Date { monthFormatter.date(from: s) ?? .distantPast }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        f.dateFormat = format
        return f
    }
}

extension Date {
    /// 例: 9/28
    var monthDay: String { formatted(.dateTime.month(.defaultDigits).day()) }
    /// 例: 2026年8月
    var yearMonth: String { formatted(.dateTime.year().month(.defaultDigits)) }
}
