import SwiftUI
import EczemaKit

/// The app frame: the four tab pages, the tab bar, the pink "+" button and everything that floats
/// above them (quick-tag sheet, HUD toast, onboarding, demo-tour touches).
struct RootView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var services = ShellServices()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The page on screen. It follows `app.tab` one run-loop later so the outgoing page can pick up
    /// the new slide direction before it leaves (otherwise SwiftUI uses the stale transition).
    @State private var shown: Tab?
    @State private var direction: CGFloat = 1

    var body: some View {
        let current = shown ?? app.tab
        ZStack(alignment: .bottom) {
            Twin.Palette.paper.ignoresSafeArea()

            // A still copy of the yellow frame behind the pages: while a page slides 24 pt sideways
            // its top bar never reveals a white strip at the screen edge.
            VStack(spacing: 0) {
                TopBar(title: " ", subtitle: " ").accessibilityHidden(true)
                Spacer(minLength: 0)
            }

            ZStack {
                page(current)
            }
            .id(current)
            .transition(pageTransition)

            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    TagButton()
                }
                .padding(.trailing, 18)
                TwinTabBar()
            }
        }
        .ignoresSafeArea(.keyboard)
        .overlay { TagSheetHost() }
        .overlay(alignment: .top) { ShellToastHost() }
        .overlay { OnboardingHost() }
        .overlayPreferenceValue(TourTargetKey.self) { anchors in
            TourTouchLayer(anchors: anchors)
        }
        .onPreferenceChange(TourTargetIDsKey.self) { ids in services.tour.targets = ids }
        .sheet(isPresented: $app.showReport) {
            ReportScreen()
                .shellEnvironment(app, services)
        }
        .sheet(isPresented: $app.showSettings) {
            SettingsScreen()
                .shellEnvironment(app, services)
        }
        .shellEnvironment(app, services)
        .onAppear {
            if shown == nil { shown = app.tab }
            services.attach(app)
        }
        .onChange(of: app.tab) { old, new in turnPage(from: old, to: new) }
        .modifier(TourStopper(tour: services.tour, app: app, toasts: services.toasts))
    }

    @ViewBuilder private func page(_ tab: Tab) -> some View {
        switch tab {
        case .today: TodayScreen()
        case .trends: TrendsScreen()
        case .insight: InsightScreen()
        case .experiment: ExperimentScreen()
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(x: direction * 24).combined(with: .opacity),
            removal: .offset(x: -direction * 24).combined(with: .opacity))
    }

    private func turnPage(from old: Tab, to new: Tab) {
        let all = Tab.allCases
        direction = (all.firstIndex(of: new) ?? 0) > (all.firstIndex(of: old) ?? 0) ? 1 : -1
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.22) : Twin.Motion.slide) { shown = new }
        }
    }
}

extension View {
    /// Everything the shell's screens and sheets read from the environment.
    func shellEnvironment(_ app: AppState, _ services: ShellServices) -> some View {
        self
            .environmentObject(app)
            .environmentObject(services)
            .environmentObject(services.toasts)
            .environmentObject(services.tour)
            .environmentObject(services.data)
            .environmentObject(services.access)
            .environmentObject(services.watch)
    }
}

/// Any real touch ends an autoplaying tour. The gesture only exists while a tour runs, so it
/// never competes with normal taps.
private struct TourStopper: ViewModifier {
    @ObservedObject var tour: DemoTour
    let app: AppState
    let toasts: ShellToasts
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded { tour.stop(app: app, toasts: toasts) },
            including: tour.isRunning ? .all : .subviews)
    }
}

// MARK: - Pink "+" button

/// Pink "+" that opens the quick-tag sheet. The only hard offset shadow in the app: pressing it
/// pushes the button down into its shadow, and the plus turns while the sheet is up.
struct TagButton: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        Button {
            withAnimation(TagSheetHost.openAnimation(reduceMotion)) { app.showTagSheet = true }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Twin.Palette.ink)
                .rotationEffect(.degrees(app.showTagSheet && !reduceMotion ? 135 : 0))
                .animation(Twin.Motion.bouncy, value: app.showTagSheet)
        }
        .buttonStyle(FABStyle())
        .scaleEffect(appeared ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(Twin.Motion.bouncy.delay(0.5)) { appeared = true } }
        .accessibilityLabel("Tag something new")
        .accessibilityHint("Opens the quick-tag sheet")
    }
}

/// Raft brand moment: pink block, ink edge, 3 pt hard ink shadow that the button sinks into.
private struct FABStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
        return ZStack {
            shape.fill(Twin.Palette.ink).offset(x: 3, y: 3)
            configuration.label
                .frame(width: 58, height: 58)
                .background(Twin.Palette.pink, in: shape)
                .overlay(shape.fill(Twin.Palette.ink.opacity(pressed ? 0.08 : 0)))
                .overlay(shape.strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                .offset(x: pressed ? 3 : 0, y: pressed ? 3 : 0)
        }
        .frame(width: 61, height: 61, alignment: .topLeading)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pressed)
        .onChange(of: pressed) { _, isDown in if isDown { Haptics.tap() } }
    }
}
