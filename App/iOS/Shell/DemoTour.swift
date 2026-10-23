import SwiftUI
import EczemaKit

// MARK: - Tour targets

/// Views the demo tour can "tap". A screen marks a control with `.tourTarget("claudeCard")`;
/// the tour then shows its touch ripple there. Unmarked targets fall back to the tab bar.
struct TourTargetKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The ids of the targets currently on screen (so the tour knows which touches it can show).
struct TourTargetIDsKey: PreferenceKey {
    static var defaultValue: Set<String> = []
    static func reduce(value: inout Set<String>, nextValue: () -> Set<String>) { value.formUnion(nextValue()) }
}

extension View {
    /// Optional: lets the `-autoplay tour` show its touch on this view.
    /// Known ids: "claudeCard" (Today), "startTest" (Insight), "fastForward" (Test), "tab.<tab>".
    func tourTarget(_ id: String) -> some View {
        anchorPreference(key: TourTargetKey.self, value: .bounds) { [id: $0] }
            .preference(key: TourTargetIDsKey.self, value: [id])
    }
}

// MARK: - Director

/// `-autoplay tour`: drives the stage story through `AppState` only (no knowledge of the other
/// screens' internals), so it works even while a screen is still a placeholder:
/// Today (4 s) → tap the Claude card → Insight reveal → Start test → Test → fast-forward to day 10
/// (result moment) → Trends. A real touch anywhere stops it. `-tourPace 1.5` slows it down.
@MainActor
final class DemoTour: ObservableObject {
    struct Touch: Equatable {
        let id = UUID()
        var primary: String
        var fallback: String?
    }

    @Published private(set) var isRunning = false
    @Published private(set) var touch: Touch?
    /// Targets currently marked on screen (updated by the root view).
    var targets: Set<String> = []
    private var task: Task<Void, Never>?

    /// Starts (or restarts) the tour after `delay` seconds.
    func start(app: AppState, delay: Double = 0.4) {
        task?.cancel()
        let pace = max(0.5, min(3, UserDefaults.standard.double(forKey: "tourPace").nonZero ?? 1))
        task = Task { [weak self] in
            await self?.run(app: app, pace: pace, delay: delay)
        }
    }

    func stop(app: AppState, toasts: ToastCenter?) {
        guard isRunning else { return }
        task?.cancel()
        task = nil
        isRunning = false
        touch = nil
        toasts?.show("Tour stopped · the app is yours", mood: .info)
    }

    private func run(app: AppState, pace: Double, delay: Double) async {
        func wait(_ s: Double) async throws { try await Task.sleep(nanoseconds: UInt64(s * pace * 1_000_000_000)) }
        func tap(_ target: String, fallback: String?) async throws {
            touch = Touch(primary: target, fallback: fallback)
            try await Task.sleep(nanoseconds: 420_000_000)
        }

        isRunning = true
        defer { if !Task.isCancelled { isRunning = false; touch = nil } }
        do {
            // Clean stage: flare story, Today, nothing on top.
            app.showTagSheet = false
            app.showReport = false
            app.showSettings = false
            app.showOnboarding = false
            if app.experimentDay != nil || !app.dataset.isDemo { app.setExperimentDay(nil) }
            app.select(.today)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            // 1. Today: how bad is it right now?
            try await wait(3.1)
            try await tap("claudeCard", fallback: "tab.insight")
            app.select(.insight)

            // 2. Insight: thinking → typed summary → suspects fly in → evidence arc.
            try await wait(6.8)
            try await tap("startTest", fallback: "tab.experiment")
            app.startExperiment()

            // 3. The test: day 1, then fast-forward to the result (a touch on the
            //    fast-forward button when the Test screen marks it, else just the days ticking).
            try await wait(1.3)
            for day in 2...10 {
                if targets.contains("fastForward") {
                    try await tap("fastForward", fallback: nil)
                    try await wait(0.1)
                } else {
                    try await wait(0.32)
                }
                app.setExperimentDay(day)
            }
            // Result moment (card flip, burst, success haptic) belongs to the Test screen.
            try await wait(3.2)

            // 4. Trends: the whole story, flare and recovery.
            try await tap("tab.trends", fallback: nil)
            app.select(.trends)
            try await wait(6)
        } catch {
            // Cancelled: leave the app where it is.
        }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

// MARK: - Touch ripple

/// Draws the tour's finger: a dot that presses in, then a ring that spreads and fades.
struct TourTouchLayer: View {
    @EnvironmentObject var tour: DemoTour
    let anchors: [String: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            if let touch = tour.touch, let anchor = anchors[touch.primary] ?? touch.fallback.flatMap({ anchors[$0] }) {
                let rect = proxy[anchor]
                TouchRipple()
                    .id(touch.id)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TouchRipple: View {
    @State private var down = false
    @State private var lifted = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Twin.Palette.ink.opacity(0.55), lineWidth: 1.5)
                .frame(width: 46, height: 46)
                .scaleEffect(lifted ? 1.9 : 1)
                .opacity(lifted ? 0 : (down ? 0.9 : 0))
            Circle()
                .fill(Twin.Palette.ink.opacity(0.22))
                .overlay(Circle().strokeBorder(Twin.Palette.paper.opacity(0.9), lineWidth: 2))
                .frame(width: 42, height: 42)
                .scaleEffect(down ? 0.86 : 1.35)
                .opacity(lifted ? 0 : (down ? 1 : 0))
        }
        .onAppear {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { down = true }
            withAnimation(.easeOut(duration: 0.55).delay(0.36)) { lifted = true }
        }
    }
}
