import Foundation
import Observation

/// 価格データの取得と保存。前回取れたデータを端末に残し、オフラインでも表示できるようにする。
@MainActor
@Observable
final class PriceStore {
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/bighide023-arch/RiceApp/main/data/prices.json")!

    private(set) var data: PriceData?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("prices.json")
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init() {
        data = Self.load(from: cacheURL) ?? Self.load(from: Bundle.main.url(forResource: "prices", withExtension: "json"))
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var request = URLRequest(url: Self.remoteURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (body, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            data = try Self.decoder.decode(PriceData.self, from: body)
            try? body.write(to: cacheURL, options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = "最新のデータを取得できませんでした。前回のデータを表示しています。"
        }
    }

    private static func load(from url: URL?) -> PriceData? {
        guard let url, let body = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(PriceData.self, from: body)
    }
}
