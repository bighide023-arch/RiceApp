import Charts
import SwiftUI

struct ContentView: View {
    @Environment(PriceStore.self) private var store
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let data = store.data {
                    VStack(spacing: 16) {
                        if let message = store.errorMessage {
                            Label(message, systemImage: "wifi.exclamationmark")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let updated = data.updatedDate {
                            Text("最終更新：\(updated.formatted(.dateTime.month(.defaultDigits).day().hour().minute()))・毎日18時ごろに確認")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        RetailSummaryCard(retail: data.retailWeekly)
                        RetailChartCard(weeks: data.retailWeekly.weeks)
                        if let forecast = data.forecast {
                            ForecastCard(forecast: forecast, weeks: data.retailWeekly.weeks)
                        }
                        if let wholesale = data.wholesaleMonthly {
                            WholesaleCard(wholesale: wholesale)
                        }
                    }
                    .padding()
                } else if store.isLoading {
                    ProgressView().padding(.top, 80)
                } else {
                    ContentUnavailableView(
                        "データがありません",
                        systemImage: "exclamationmark.triangle",
                        description: Text(store.errorMessage ?? "下に引っぱって再読み込みしてください。")
                    )
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("お米の相場")
            .toolbar {
                Button("データについて", systemImage: "info.circle") { showingAbout = true }
            }
            .sheet(isPresented: $showingAbout) { AboutView() }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
        }
    }
}

// MARK: - 店頭価格

struct RetailSummaryCard: View {
    let retail: RetailWeekly

    var body: some View {
        Card {
            if let latest = retail.weeks.last {
                VStack(alignment: .leading, spacing: 8) {
                    Text("スーパーの平均価格（5kg）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(latest.average.formatted())
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("円").font(.title3)
                    }
                    if retail.weeks.count >= 2 {
                        ChangeLabel(current: latest.average, previous: retail.weeks[retail.weeks.count - 2].average, suffix: "前週比")
                    }
                    Text("\(latest.startDate.monthDay)〜\(latest.endDate.monthDay)の週・全国約1,000店")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        PriceColumn(title: "銘柄米", price: latest.brand)
                        PriceColumn(title: "ブレンド米等", price: latest.blend)
                    }
                }
            }
        }
    }
}

struct PriceColumn: View {
    let title: String
    let price: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(price.formatted())円").font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChangeLabel: View {
    let current: Int
    let previous: Int
    let suffix: String

    var body: some View {
        let diff = current - previous
        let percent = previous == 0 ? 0 : Double(diff) / Double(previous)
        let sign = diff > 0 ? "+" : (diff < 0 ? "−" : "±")
        Text("\(suffix) \(sign)\(abs(diff).formatted())円（\(sign)\(abs(percent).formatted(.percent.precision(.fractionLength(1)))))")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(diff > 0 ? Color.red : (diff < 0 ? Color.blue : Color.secondary))
    }
}

enum ChartRange: String, CaseIterable, Identifiable {
    case threeMonths = "3か月"
    case halfYear = "半年"
    case year = "1年"
    case all = "全期間"

    var id: String { rawValue }

    func filter<T>(_ items: [T], date: (T) -> Date) -> [T] {
        let months: Int
        switch self {
        case .threeMonths: months = 3
        case .halfYear: months = 6
        case .year: months = 12
        case .all: return items
        }
        guard let last = items.last.map(date),
              let from = Calendar.current.date(byAdding: .month, value: -months, to: last) else { return items }
        return items.filter { date($0) >= from }
    }
}

struct RetailChartCard: View {
    let weeks: [RetailWeek]
    @State private var range: ChartRange = .halfYear
    @State private var showBreakdown = false

    var body: some View {
        let shown = range.filter(weeks, date: \.startDate)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("店頭価格の推移").font(.headline)
                Picker("期間", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Chart {
                    ForEach(shown) { w in
                        LineMark(x: .value("週", w.startDate), y: .value("円", w.average))
                            .foregroundStyle(by: .value("種類", "全平均"))
                        if showBreakdown {
                            LineMark(x: .value("週", w.startDate), y: .value("円", w.brand))
                                .foregroundStyle(by: .value("種類", "銘柄米"))
                            LineMark(x: .value("週", w.startDate), y: .value("円", w.blend))
                                .foregroundStyle(by: .value("種類", "ブレンド米等"))
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "全平均": Color.accentColor,
                    "銘柄米": Color.orange,
                    "ブレンド米等": Color.gray,
                ])
                .chartLegend(showBreakdown ? .visible : .hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)

                Toggle("銘柄米・ブレンド米等も表示", isOn: $showBreakdown)
                    .font(.subheadline)
                Text("単位：円/5kg（税込）").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 見通し

struct ForecastCard: View {
    let forecast: Forecast
    let weeks: [RetailWeek]

    var body: some View {
        let recent = Array(weeks.suffix(12))
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("今後の見通し（参考）").font(.headline)
                    Spacer()
                    Text(forecast.directionLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(directionColor)
                }
                if let target = forecast.weeks.dropFirst(3).first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("4週後（\(target.startDate.monthDay)〜の週）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("約\(target.mid.formatted())円")
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                            Text("（\(target.low.formatted())〜\(target.high.formatted())円）")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Chart {
                    ForEach(recent) { w in
                        LineMark(x: .value("週", w.startDate), y: .value("円", w.average))
                            .foregroundStyle(by: .value("種類", "実際"))
                    }
                    ForEach(forecast.weeks) { w in
                        AreaMark(
                            x: .value("週", w.startDate),
                            yStart: .value("下", w.low),
                            yEnd: .value("上", w.high)
                        )
                        .foregroundStyle(Color.orange.opacity(0.15))
                        LineMark(x: .value("週", w.startDate), y: .value("円", w.mid))
                            .foregroundStyle(by: .value("種類", "予想"))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                }
                .chartForegroundStyleScale(["実際": Color.accentColor, "予想": Color.orange])
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)

                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var directionColor: Color {
        switch forecast.direction {
        case "up": Color.red
        case "down": Color.blue
        default: Color.secondary
        }
    }

    private var note: String {
        var text = "過去の店頭価格の動きだけから計算した目安です。政策の変更や天候などのニュースは反映していません。色の帯は、およそ8割の確率で入ると見込む範囲です。"
        if let b = forecast.backtest {
            text += "過去に同じ方法で\(b.weeksAhead)週先を予想した場合、平均で約\(b.modelMae)円ずれました。"
        }
        return text
    }
}

// MARK: - 相対取引価格

struct WholesaleCard: View {
    let wholesale: WholesaleMonthly

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("産地と卸の取引価格（相対取引価格）").font(.headline)
                if let latest = wholesale.average.last {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(latest.price.formatted())
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("円/60kg").font(.subheadline)
                    }
                    if wholesale.average.count >= 2 {
                        ChangeLabel(current: latest.price, previous: wholesale.average[wholesale.average.count - 2].price, suffix: "前月比")
                    }
                    Text("\(latest.date.yearMonth)・全銘柄平均（玄米）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                MonthlyChart(prices: wholesale.average)
                NavigationLink {
                    BrandListView(wholesale: wholesale)
                } label: {
                    HStack {
                        Text("銘柄別に見る（\(wholesale.brands.count)銘柄）")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

struct MonthlyChart: View {
    let prices: [MonthPrice]

    var body: some View {
        Chart(prices) { p in
            LineMark(x: .value("月", p.date, unit: .month), y: .value("円", p.price))
            PointMark(x: .value("月", p.date, unit: .month), y: .value("円", p.price))
                .symbolSize(20)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 180)
    }
}

// MARK: - 共通

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView().environment(PriceStore())
}
