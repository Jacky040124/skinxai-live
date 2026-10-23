import SwiftUI
import EczemaKit

/// Watch app state.
///
/// Launch arguments (scripts/watchshot): -screen ring|prompt|recent
@MainActor
final class WatchModel: ObservableObject {
    enum Screen: String { case ring, prompt, recent }
    @Published var screen: Screen = .ring
    @Published var showPrompt = false
    @Published private(set) var dataset: TwinDataset

    init() {
        dataset = DemoData.make(today: Date())
        if let s = UserDefaults.standard.string(forKey: "screen"), let screen = Screen(rawValue: s) {
            self.screen = screen
            showPrompt = screen == .prompt
        }
    }
}
