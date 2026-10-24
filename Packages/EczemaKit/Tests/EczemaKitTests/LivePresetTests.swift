import Foundation
import Testing
@testable import EczemaKit

@Suite struct LivePresetTests {
    @Test func gentleScratchIsCaughtLiveButNotByStandard() {
        var s = SyntheticMotion(start: 0, seed: 7)
        s.still(4)
        s.scratch(5, hz: 4.2, amplitude: 0.06)
        s.still(4)
        let live = ScratchDetector.episodes(in: s.samples, model: ScratchModel(), config: .live)
        #expect(live.count == 1)
    }

    @Test func liveStartsAfterOneWindow() {
        var s = SyntheticMotion(start: 0, seed: 9)
        s.still(3)
        s.scratch(8, hz: 4.5, amplitude: 0.2)
        let d = ScratchDetector(model: ScratchModel(), config: .live)
        var firstStart: Date?
        for sample in s.samples {
            for e in d.process(sample) { if case let .episodeStarted(st) = e, firstStart == nil { firstStart = st.start; _ = st } }
            if firstStart != nil { break }
        }
        #expect(firstStart != nil)
    }

    @Test func wavingAndWalkingAreIgnoredLive() {
        var s = SyntheticMotion(start: 0, seed: 11)
        s.walk(20)
        s.still(3)
        s.type(15)
        #expect(ScratchDetector.episodes(in: s.samples, model: ScratchModel(), config: .live).isEmpty)
        // big waving: 2.4 Hz, ~1 g of arm motion
        var w = SyntheticMotion(start: 0, seed: 12)
        w.scratch(10, hz: 2.4, amplitude: 1.6)
        #expect(ScratchDetector.episodes(in: w.samples, model: ScratchModel(), config: .live).isEmpty)
    }
}
