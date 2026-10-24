import SwiftUI
import EczemaKit

@main
struct EczemaTwinApp: App {
    @StateObject private var app = AppState()

    init() {
        // The watch link starts with the process: WatchConnectivity may wake the app in the
        // background to deliver episodes, and then no screen appears.
        WatchInbox.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.light)
                .tint(Twin.Palette.ink)
        }
    }
}
