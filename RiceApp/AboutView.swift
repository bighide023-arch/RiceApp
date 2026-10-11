import SwiftUI

struct AboutView: View {
    @Environment(PriceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let data = store.data {
                    Section("スーパーの平均価格") {
                        Text("全国約1,000店のスーパーのPOSデータによる、5kg袋の週ごとの平均販売価格（税込）です。国の公表は週1回（金曜ごろ）で、アプリは毎日確認して新しい数字が出たらその日のうちに反映します。")
                        SourceLink(source: data.retailWeekly.source, url: data.retailWeekly.sourceUrl)
                    }
                    if let wholesale = data.wholesaleMonthly {
                        Section("相対取引価格") {
                            Text("JAなどの出荷業者と卸売業者の間で決まった玄米60kgあたりの取引価格（税込）です。毎月公表されます。")
                            SourceLink(source: wholesale.source, url: wholesale.sourceUrl)
                        }
                    }
                }
                if let forecast = store.data?.forecast {
                    Section("今後の見通し") {
                        Text("店頭価格の過去の動きから、\(forecast.method.replacingOccurrences(of: "（過去の店頭価格のみ）", with: ""))で8週先までを計算した目安です。将来の値段を保証するものではありません。")
                    }
                }
                Section {
                    Text("このアプリは農林水産省の公表データ（公共データ利用規約 第1.0版）を加工して作成しています。国が作成したものではありません。")
                    Text("表示内容の正確性は保証されません。最新の情報は出典元でご確認ください。")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("データについて")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("閉じる") { dismiss() }
            }
        }
    }
}

private struct SourceLink: View {
    let source: String
    let url: String

    var body: some View {
        if let link = URL(string: url) {
            Link(destination: link) {
                Label("出典：\(source)", systemImage: "arrow.up.right.square")
                    .font(.footnote)
            }
        }
    }
}
