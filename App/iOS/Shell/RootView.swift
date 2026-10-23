import SwiftUI
import EczemaKit

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            Twin.Palette.paper.ignoresSafeArea()

            ZStack {
                switch app.tab {
                case .today: TodayScreen()
                case .trends: TrendsScreen()
                case .insight: InsightScreen()
                case .experiment: ExperimentScreen()
                }
            }
            .id(app.tab)
            .transition(.asymmetric(
                insertion: .offset(x: CGFloat(app.tabDirection) * 28).combined(with: .opacity),
                removal: .offset(x: CGFloat(-app.tabDirection) * 28).combined(with: .opacity)))

            TwinTabBar()
        }
        .overlay(alignment: .bottomTrailing) { TagButton().padding(.trailing, 18).padding(.bottom, 104) }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $app.showTagSheet) { TagSheet().environmentObject(app) }
        .sheet(isPresented: $app.showReport) { ReportScreen().environmentObject(app) }
        .sheet(isPresented: $app.showSettings) { SettingsScreen().environmentObject(app) }
        .fullScreenCover(isPresented: $app.showOnboarding) { OnboardingScreen().environmentObject(app) }
    }
}

/// Pink "+" that opens the quick-tag sheet.
struct TagButton: View {
    @EnvironmentObject var app: AppState
    @State private var appeared = false
    var body: some View {
        Button { app.showTagSheet = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 58, height: 58)
                .background(Twin.Palette.pink, in: RoundedRectangle(cornerRadius: Twin.Radius.control))
                .background(Twin.Palette.ink, in: RoundedRectangle(cornerRadius: Twin.Radius.control).offset(x: 3, y: 3))
                .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(appeared ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(Twin.Motion.bouncy.delay(0.5)) { appeared = true } }
        .accessibilityLabel("Tag something new")
    }
}
