import SwiftUI
import EczemaKit

/// PLACEHOLDER — replaced by the agent that owns App/iOS/Screens/Trends.
struct TrendsScreen: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ScreenScaffold(title: "Trends", subtitle: "coming soon") { UserAvatar() } content: {
            Text("Trends").font(Twin.Typeface.title).twinCard().riseIn(0.05)
        }
    }
}
