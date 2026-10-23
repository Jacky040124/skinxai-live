import SwiftUI
import EczemaKit

/// PLACEHOLDER — replaced by the agent that owns App/iOS/Screens/Tag.
struct TagSheet: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anything new today?").font(Twin.Typeface.title)
            Button("Save") { app.showTagSheet = false }.buttonStyle(TwinButtonStyle(fill: Twin.Palette.yellow))
        }
        .padding(20)
        .presentationDetents([.medium])
    }
}
