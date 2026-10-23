import SwiftUI
import EczemaKit

@main
struct EczemaTwinApp: App {
    @StateObject private var app = AppState()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.light)
                .tint(Twin.Palette.ink)
        }
    }
}
