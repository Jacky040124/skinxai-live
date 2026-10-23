import SwiftUI
import EczemaKit

/// PLACEHOLDER — replaced by the agent that owns App/iOS/Screens/Onboarding.
struct OnboardingScreen: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(spacing: 20) {
            Text("Eczema Twin").font(Twin.Typeface.largeTitle)
            Button("Start") { app.showOnboarding = false }.buttonStyle(TwinButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Twin.Palette.frame)
    }
}
