import SwiftUI
import EczemaKit

/// Demo time travel that keeps a live analysis.
///
/// `AppState.startExperiment()` / `setExperimentDay(_:)` rebuild Douglas's story from `DemoData`, which
/// always carries the bundled case file. After a live re-run on stage that would quietly swap Claude's live
/// answer (and its test plan) for the bundled one. The Insight and Test screens go through these wrappers:
/// they put the live case file back and run its plan through the scripted test. Real data is untouched
/// (`AppState` handles real mode itself).
@MainActor
enum StoryTravel {
    /// Days of the scripted test in the demo story.
    static let storyTestLength = DemoData.experimentMinutes.count

    static func startExperiment(app: AppState) {
        let live = liveCaseFile(in: app.dataset)
        app.startExperiment()
        restore(live, app: app)
    }

    static func setExperimentDay(_ day: Int?, app: AppState) {
        let live = liveCaseFile(in: app.dataset)
        app.setExperimentDay(day)
        restore(live, app: app)
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

    private static func restore(_ live: CaseFile?, app: AppState) {
        guard let live, app.dataset.isDemo else { return }
        app.update { d in
            d.caseFile = live
            if var e = d.experiment, let plan = storyPlan(for: live) {
                e.plan = plan
                d.experiment = e
            }
        }
    }
}
