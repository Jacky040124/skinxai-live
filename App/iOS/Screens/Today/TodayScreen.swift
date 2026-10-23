import SwiftUI
import EczemaKit

/// PLACEHOLDER — replaced by the agent that owns App/iOS/Screens/Today.
struct TodayScreen: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ScreenScaffold(title: "Today", subtitle: "coming soon") { UserAvatar() } content: {
            Text("Today").font(Twin.Typeface.title).twinCard().riseIn(0.05)
        }
    }
}
