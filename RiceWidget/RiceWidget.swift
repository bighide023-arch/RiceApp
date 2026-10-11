import SwiftUI
import WidgetKit

/// ホーム画面のウィジェット。アプリと同じ JSON を直接読み、最新のスーパー平均価格を出す。
struct PriceEntry: TimelineEntry {
    let date: Date
    let latest: RetailWeek?
    let previous: RetailWeek?
    let wholesale: MonthPrice?
}

struct PriceProvider: TimelineProvider {
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/bighide023-arch/RiceApp/main/data/prices.json")!

    func placeholder(in context: Context) -> PriceEntry {
        PriceEntry(
            date: .now,
            latest: RetailWeek(weekStart: "2026-09-28", weekEnd: "2026-10-04", brand: 3200, blend: 2500, average: 2860),
            previous: RetailWeek(weekStart: "2026-09-21", weekEnd: "2026-09-27", brand: 3250, blend: 2550, average: 2900),
            wholesale: MonthPrice(month: "2026-08", price: 31556)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PriceEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await fetchEntry() ?? placeholder(in: context)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PriceEntry>) -> Void) {
        Task {
            let entry = await fetchEntry() ?? PriceEntry(date: .now, latest: nil, previous: nil, wholesale: nil)
            // データは毎日18時ごろ更新されるので、数時間おきに見に行けば十分
            let next = Calendar.current.date(byAdding: .hour, value: 6, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func fetchEntry() async -> PriceEntry? {
        var request = URLRequest(url: Self.remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (body, _) = try? await URLSession.shared.data(for: request) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = try? decoder.decode(PriceData.self, from: body) else { return nil }
        let weeks = data.retailWeekly.weeks
        return PriceEntry(
            date: .now,
            latest: weeks.last,
            previous: weeks.count >= 2 ? weeks[weeks.count - 2] : nil,
            wholesale: data.wholesaleMonthly?.average.last
        )
    }
}

struct RiceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PriceEntry

    var body: some View {
        if let latest = entry.latest {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("スーパー平均 5kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(latest.average.formatted())
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                        Text("円").font(.caption)
                    }
                    if let previous = entry.previous {
                        change(current: latest.average, previous: previous.average)
                    }
                    Spacer(minLength: 0)
                    Text("\(latest.endDate.monthDay)までの週")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if family == .systemMedium {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        PriceRow(title: "銘柄米", price: latest.brand)
                        PriceRow(title: "ブレンド米等", price: latest.blend)
                        if let wholesale = entry.wholesale {
                            PriceRow(title: "取引価格 60kg（\(wholesale.date.formatted(.dateTime.month(.defaultDigits)))）", price: wholesale.price)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("データを読み込めませんでした")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func change(current: Int, previous: Int) -> some View {
        let diff = current - previous
        let sign = diff > 0 ? "+" : (diff < 0 ? "−" : "±")
        return Text("前週比 \(sign)\(abs(diff).formatted())円")
            .font(.caption.weight(.medium))
            .foregroundStyle(diff > 0 ? Color.red : (diff < 0 ? Color.blue : Color.secondary))
    }
}

private struct PriceRow: View {
    let title: String
    let price: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text("\(price.formatted())円").font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

struct RiceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RiceWidget", provider: PriceProvider()) { entry in
            RiceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("お米の相場")
        .description("スーパーでのお米5kgの全国平均価格を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct RiceWidgetBundle: WidgetBundle {
    var body: some Widget {
        RiceWidget()
    }
}
