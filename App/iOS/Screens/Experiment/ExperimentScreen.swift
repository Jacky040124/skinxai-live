import SwiftUI
import EczemaKit

/// PLACEHOLDER — replaced by the agent that owns App/iOS/Screens/Experiment.
struct ExperimentScreen: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ScreenScaffold(title: "Experiment", subtitle: "coming soon") { UserAvatar() } content: {
            Text("Experiment").font(Twin.Typeface.title).twinCard().riseIn(0.05)
        }
    }
}
