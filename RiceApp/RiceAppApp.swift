import SwiftUI

@main
struct RiceAppApp: App {
    @State private var store = PriceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
