import SwiftUI
import EczemaKit

/// PLACEHOLDER — replaced by the agent that owns App/iOS/Screens/Insight.
struct InsightScreen: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ScreenScaffold(title: "Insight", subtitle: "coming soon") { UserAvatar() } content: {
            Text("Insight").font(Twin.Typeface.title).twinCard().riseIn(0.05)
        }
    }
}
