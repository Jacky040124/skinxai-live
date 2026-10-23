import SwiftUI
import EczemaKit

@main
struct EczemaTwinWatchApp: App {
    @StateObject private var model = WatchModel()
    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(model)
        }
    }
}
