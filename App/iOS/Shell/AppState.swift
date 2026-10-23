import SwiftUI
import EczemaKit

enum Tab: String, CaseIterable, Identifiable {
    case today, trends, insight, experiment
    var id: String { rawValue }
    var title: String {
        switch self { case .today: "Today"; case .trends: "Trends"; case .insight: "Insight"; case .experiment: "Test" }
    }
    /// SF Symbol for the tab bar.
    var icon: String {
        switch self {
        case .today: "circle.lefthalf.filled"
        case .trends: "chart.bar.fill"
        case .insight: "sparkle"
        case .experiment: "flask"
        }
    }
}

/// App-wide state. Screens read `dataset` and call the intents below.
///
/// Launch arguments (used by scripts/shot and for the demo):
///   -screen today|trends|insight|experiment|tag|onboarding|report|settings
///   -expDay 1...10      start in the experiment story at that day (demo time travel)
///   -storyDay 1...13    start on that day of the flare story (shell; no case file before day 14)
///   -dataMode real|demo use your own data (watch, Health, weather) or the demo story (shell)
///   -autoplay tour      run the scripted demo tour (owned by the shell agent)
@MainActor
final class AppState: ObservableObject {
    @Published var tab: Tab = .today
    /// Direction of the last tab change (for slide transitions): +1 = to the right.
    @Published private(set) var tabDirection: Int = 1
    @Published var showTagSheet = false
    @Published var showOnboarding = false
    @Published var showReport = false
    @Published var showSettings = false
    @Published private(set) var dataset: TwinDataset
    /// Demo time travel: nil = the flare story (today = day 14); 1...10 = day of the 10-day test.
    @Published private(set) var experimentDay: Int?

    init() {
        let defaults = UserDefaults.standard
        let exp = defaults.string(forKey: "expDay").flatMap(Int.init)
        experimentDay = exp
        dataset = DemoData.make(today: Date(), experimentDay: exp)
        // Real data mode (Settings → Demo story off): start from what is stored on the phone.
        if exp == nil, DataModeController.launchMode == .real { dataset = DataModeController.storedRealDataset() }
        if let screen = defaults.string(forKey: "screen") { route(screen) }
    }

    func route(_ screen: String) {
        switch screen {
        case "today", "trends", "insight", "experiment": tab = Tab(rawValue: screen)!
        case "tag": showTagSheet = true
        case "onboarding": showOnboarding = true
        case "report": showReport = true
        case "settings": showSettings = true
        default: break
        }
    }

    func select(_ new: Tab) {
        guard new != tab else { return }
        let all = Tab.allCases
        tabDirection = (all.firstIndex(of: new)! > all.firstIndex(of: tab)!) ? 1 : -1
        Haptics.tap()
        withAnimation(Twin.Motion.slide) { tab = new }
    }

    /// Starts the 10-day test suggested by the case file (demo: day 1 of the experiment story).
    func startExperiment() {
        if !dataset.isDemo { startRealExperiment(); return }
        setExperimentDay(1)
        select(.experiment)
        Haptics.success()
    }

    /// Real data mode: starts the case file's suggested test today (no time travel).
    func startRealExperiment() {
        if let plan = dataset.caseFile?.nextExperiment {
            let recent = dataset.days.suffix(7).map(\.scratchMinutes)
            let before = recent.isEmpty ? dataset.baselineMinutesPerDay : recent.reduce(0, +) / Double(recent.count)
            let start = Calendar.current.startOfDay(for: Date())
            update { $0.experiment = Experiment(plan: plan, startDay: start, baselineMinutesPerDay: before) }
            Haptics.success()
        }
        select(.experiment)
    }

    /// Demo time travel inside the experiment (e.g. "Fast-forward 5 days").
    func setExperimentDay(_ day: Int?) {
        withAnimation(Twin.Motion.spring) {
            experimentDay = day.map { min(max($0, 1), 10) }
            dataset = DemoData.make(today: Date(), experimentDay: experimentDay)
        }
    }

    /// Replace the dataset (live data, a new case file, user tags...).
    func update(_ change: (inout TwinDataset) -> Void) {
        var d = dataset
        change(&d)
        withAnimation(Twin.Motion.spring) { dataset = d }
    }
}
