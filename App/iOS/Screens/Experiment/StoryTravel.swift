import SwiftUI
import EczemaKit

/// Demo time travel that keeps a live analysis.
///
/// `AppState.startExperiment()` / `setExperimentDay(_:)` rebuild Douglas's story from `DemoData`, which
/// always carries the bundled case file. After a live re-run on stage that would quietly swap Claude's live
/// answer (and its test plan) for the bundled one. The Insight and Test screens go through these wrappers:
/// they put the live case file back, run its plan through the scripted test, and move its dates with the
/// story (time travel keeps today as today, so every story day gets a new date). Real data is untouched
/// (`AppState` handles real mode itself).
@MainActor
enum StoryTravel {
    /// Days of the scripted test in the demo story.
    static let storyTestLength = DemoData.experimentMinutes.count

    /// - Parameter storyDay: the flare-story day on screen (Settings time travel), when no test runs.
    static func startExperiment(app: AppState, storyDay: Int = StoryPoint.flareLength) {
        let live = liveCaseFile(in: app.dataset)
        let before = position(app, storyDay: storyDay)
        app.startExperiment()
        restore(live, from: before, app: app)
    }

    static func setExperimentDay(_ day: Int?, app: AppState, storyDay: Int = StoryPoint.flareLength) {
        let live = liveCaseFile(in: app.dataset)
        let before = position(app, storyDay: storyDay)
        app.setExperimentDay(day)
        restore(live, from: before, app: app)
    }

    /// Where "today" sits in the whole story: flare days 1...14, then the test days 15...24.
    private static func position(_ app: AppState, storyDay: Int) -> Int {
        app.experimentDay.map { StoryPoint.flareLength + $0 } ?? storyDay
    }

    /// The test that will actually run for this case file. Real data: Claude's plan as written. Demo story:
    /// the live plan when it tests the story's trigger (the scripted days are a 10-day pause of the body
    /// wash), otherwise the scripted plan, so the button and the Test screen always agree.
    static func plan(for caseFile: CaseFile, in dataset: TwinDataset) -> ExperimentPlan? {
        guard dataset.isDemo, !caseFile.isBundled, caseFile.nextExperiment != nil else { return caseFile.nextExperiment }
        return storyPlan(for: caseFile) ?? InsightService.bundledCaseFile(for: dataset).nextExperiment
    }

    /// A live plan adapted to the scripted test, or nil when it doesn't fit the story.
    private static func storyPlan(for caseFile: CaseFile) -> ExperimentPlan? {
        guard !caseFile.isBundled, var plan = caseFile.nextExperiment, plan.subject != nil,
              plan.trigger == nil || plan.trigger == .newProduct else { return nil }
        plan.trigger = .newProduct
        plan.lengthDays = storyTestLength
        return plan
    }

    private static func liveCaseFile(in dataset: TwinDataset) -> CaseFile? {
        guard dataset.isDemo, let caseFile = dataset.caseFile, !caseFile.isBundled else { return nil }
        return caseFile
    }

    private static func restore(_ live: CaseFile?, from before: Int, app: AppState) {
        guard let live, app.dataset.isDemo else { return }
        // A story day that was `before - after` days from today is now that much further back (or forward).
        let after = position(app, storyDay: StoryPoint.flareLength)
        let moved = live.shiftingDates(byDays: before - after)
        app.update { d in
            d.caseFile = moved
            if var e = d.experiment, let plan = storyPlan(for: moved) {
                e.plan = plan
                d.experiment = e
            }
        }
    }
}
