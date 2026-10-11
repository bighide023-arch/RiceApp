import Charts
import SwiftUI

/// 銘柄別の相対取引価格。地方・品種でまとめたり、高い順に並べたりできる。
struct BrandListView: View {
    let wholesale: WholesaleMonthly
    @State private var query = ""
    @State private var grouping: Grouping = .area
    @State private var order: Order = .priceHigh
    @AppStorage("favoriteBrands") private var favoriteIDs = ""

    enum Grouping: String, CaseIterable, Identifiable {
        case area = "地方別"
        case variety = "品種別"
        case none = "すべて"
        var id: String { rawValue }
    }

    enum Order: String, CaseIterable, Identifiable {
        case priceHigh = "高い順"
        case priceLow = "安い順"
        case region = "産地順"
        var id: String { rawValue }
    }

    private var filtered: [BrandPrice] {
        let hits = query.isEmpty
            ? wholesale.brands
            : wholesale.brands.filter { $0.region.contains(query) || $0.variety.contains(query) }
        return hits.sorted(by: order.areInIncreasingOrder)
    }

    private var sections: [(title: String, brands: [BrandPrice])] {
        switch grouping {
        case .none:
            return [("", filtered)]
        case .area:
            let groups = Dictionary(grouping: filtered) { Area.of($0.region) }
            return Area.allCases.compactMap { area in
                groups[area].map { (area.rawValue, $0) }
            }
        case .variety:
            let groups = Dictionary(grouping: filtered) { $0.varietyGroup }
            // 銘柄の多い品種から並べる
            return groups.sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
                .map { ($0.key, $0.value) }
        }
    }

    private var favorites: [BrandPrice] {
        let ids = Set(favoriteIDs.split(separator: ",").map(String.init))
        return filtered.filter { ids.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                Picker("まとめ方", selection: $grouping) {
                    ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if !favorites.isEmpty {
                Section("お気に入り") {
                    ForEach(favorites) { row($0) }
                }
            }
            ForEach(sections, id: \.title) { section in
                Section(section.title.isEmpty ? "\(section.brands.count)銘柄" : "\(section.title)（\(section.brands.count)）") {
                    ForEach(section.brands) { row($0) }
                }
            }
        }
        .searchable(text: $query, prompt: "産地・銘柄で探す（例：コシヒカリ）")
        .navigationTitle("銘柄別の取引価格")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Picker("並べ方", selection: $order) {
                    ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label("並べ方", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    private func row(_ brand: BrandPrice) -> some View {
        NavigationLink {
            BrandDetailView(brand: brand, wholesale: wholesale)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(brand.variety)
                    Text(brand.region).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let latest = brand.latest {
                    VStack(alignment: .trailing) {
                        Text("\(latest.price.formatted())円").monospacedDigit()
                        if let diff = wholesale.differenceFromAverage(latest) {
                            Text("平均\(diff >= 0 ? "+" : "−")\(abs(diff).formatted())円")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } else {
                    Text("取引なし").foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension BrandListView.Order {
    func areInIncreasingOrder(_ a: BrandPrice, _ b: BrandPrice) -> Bool {
        switch self {
        case .priceHigh: (a.latest?.price ?? 0) > (b.latest?.price ?? 0)
        case .priceLow: (a.latest?.price ?? .max) < (b.latest?.price ?? .max)
        case .region: (Area.of(a.region).order, a.region, a.variety) < (Area.of(b.region).order, b.region, b.variety)
        }
    }
}

struct BrandDetailView: View {
    let brand: BrandPrice
    let wholesale: WholesaleMonthly
    @AppStorage("favoriteBrands") private var favoriteIDs = ""

    private var isFavorite: Bool {
        favoriteIDs.split(separator: ",").contains(Substring(brand.id))
    }

    /// 同じ品種の、ほかの産地
    private var peers: [BrandPrice] {
        wholesale.brands
            .filter { $0.varietyGroup == brand.varietyGroup && $0.id != brand.id && $0.latest != nil }
            .sorted { ($0.latest?.price ?? 0) > ($1.latest?.price ?? 0) }
    }

    var body: some View {
        List {
            if let latest = brand.latest {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(latest.price.formatted())
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("円/60kg").font(.subheadline)
                        }
                        let prices = brand.sortedPrices
                        if prices.count >= 2 {
                            ChangeLabel(current: latest.price, previous: prices[prices.count - 2].price, suffix: "前月比")
                        }
                        if let diff = wholesale.differenceFromAverage(latest) {
                            Text("全銘柄平均より\(abs(diff).formatted())円\(diff >= 0 ? "高い" : "安い")（\(latest.date.yearMonth)）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Chart {
                    ForEach(brand.sortedPrices) { p in
                        LineMark(x: .value("月", p.date, unit: .month), y: .value("円", p.price))
                            .foregroundStyle(by: .value("種類", "この銘柄"))
                        PointMark(x: .value("月", p.date, unit: .month), y: .value("円", p.price))
                            .foregroundStyle(by: .value("種類", "この銘柄"))
                            .symbolSize(20)
                    }
                    ForEach(wholesale.average) { p in
                        LineMark(x: .value("月", p.date, unit: .month), y: .value("円", p.price))
                            .foregroundStyle(by: .value("種類", "全銘柄平均"))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                .chartForegroundStyleScale(["この銘柄": Color.accentColor, "全銘柄平均": Color.gray])
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
                .padding(.vertical, 8)
            } footer: {
                Text("単位：円/玄米60kg（税込）。取引量が少ない月は公表されません。")
            }
            if !peers.isEmpty {
                Section("ほかの産地の\(brand.varietyGroup)") {
                    ForEach(peers) { peer in
                        NavigationLink {
                            BrandDetailView(brand: peer, wholesale: wholesale)
                        } label: {
                            LabeledContent(peer.region, value: "\(peer.latest!.price.formatted())円")
                        }
                    }
                }
            }
            Section("月ごとの価格") {
                ForEach(brand.sortedPrices.reversed()) { p in
                    LabeledContent(p.date.yearMonth, value: "\(p.price.formatted())円")
                }
            }
        }
        .navigationTitle("\(brand.region) \(brand.variety)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(isFavorite ? "お気に入りから外す" : "お気に入りに追加", systemImage: isFavorite ? "star.fill" : "star") {
                toggleFavorite()
            }
        }
    }

    private func toggleFavorite() {
        var ids = favoriteIDs.split(separator: ",").map(String.init)
        if let i = ids.firstIndex(of: brand.id) {
            ids.remove(at: i)
        } else {
            ids.append(brand.id)
        }
        favoriteIDs = ids.joined(separator: ",")
    }
}

/// 産地（都道府県）をまとめる地方区分
enum Area: String, CaseIterable {
    case hokkaidoTohoku = "北海道・東北"
    case kanto = "関東"
    case hokurikuChubu = "北陸・中部"
    case kinki = "近畿"
    case chugokuShikoku = "中国・四国"
    case kyushu = "九州"

    var order: Int { Self.allCases.firstIndex(of: self)! }

    static func of(_ region: String) -> Area {
        switch region {
        case "北海道", "青森", "岩手", "宮城", "秋田", "山形", "福島": .hokkaidoTohoku
        case "茨城", "栃木", "群馬", "埼玉", "千葉", "東京", "神奈川": .kanto
        case "新潟", "富山", "石川", "福井", "山梨", "長野", "岐阜", "静岡", "愛知": .hokurikuChubu
        case "三重", "滋賀", "京都", "大阪", "兵庫", "奈良", "和歌山": .kinki
        case "鳥取", "島根", "岡山", "広島", "山口", "徳島", "香川", "愛媛", "高知": .chugokuShikoku
        default: .kyushu
        }
    }
}

extension BrandPrice {
    /// 「コシヒカリ（一般）」なども「コシヒカリ」にまとめた品種名
    var varietyGroup: String {
        variety.split(separator: "（").first.map(String.init) ?? variety
    }
}

extension WholesaleMonthly {
    /// その月の全銘柄平均との差（円）。平均が公表されていない月は nil
    func differenceFromAverage(_ price: MonthPrice) -> Int? {
        average.first { $0.month == price.month }.map { price.price - $0.price }
    }
}
