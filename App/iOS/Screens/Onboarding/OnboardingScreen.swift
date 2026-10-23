import SwiftUI
import EczemaKit

/// Shows onboarding above the whole app (first launch, `-screen onboarding`, Settings → Replay).
struct OnboardingHost: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ZStack {
            if app.showOnboarding {
                OnboardingScreen()
                    .transition(.opacity)
            }
        }
        .animation(Twin.Motion.slide, value: app.showOnboarding)
    }
}

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
