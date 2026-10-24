import SwiftUI
import Combine
import EczemaKit

/// Owns the app-frame services and wires them to `AppState` once, when the root view appears.
@MainActor
final class ShellServices: ObservableObject {
    let toasts = ShellToasts()
    let access = DeviceAccess()
    /// Already active since launch (see `WatchInbox`).
    let watch = WatchInbox.shared
    private var attached = false
    private var bag = Set<AnyCancellable>()

    func attach(_ app: AppState) {
        guard !attached else { return }
        attached = true
        watch.activate()
        // Tonight's scratching reaches the phone through the live relay (`LiveSession`). Episodes the
        // watch also hands over through WatchConnectivity are only kept on the phone, without a toast.
        watch.onEpisodes = { episodes in _ = RealStore.storeEpisodes(episodes) }
        Task { await access.refresh() }

        // The watch starts tracking sleep: whatever was open, the phone shows Today, where the
        // Live sticker appears next to the avatar. `running` (not `tracking`) so a few seconds of
        // network silence in the middle of the night, which hides and shows the sticker again,
        // never pulls the phone away from another tab.
        LiveSession.shared.$running
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak app] _ in
                guard let app else { return }
                if app.showPermissions { app.showPermissions = false }
                app.select(.today, haptic: false)
            }
            .store(in: &bag)
    }
}
