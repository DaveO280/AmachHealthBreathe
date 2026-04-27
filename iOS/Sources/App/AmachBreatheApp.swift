import SwiftUI
import AmachBreatheShared

@main
struct AmachBreatheApp: App {

    @StateObject private var walletService = WalletService.shared

    init() {
        WalletService.shared.initializePrivy()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletService)
        }
    }
}
