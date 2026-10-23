import Foundation
import Testing
@testable import EczemaKit

/// Scratch detection on synthetic wrist signals (SPEC §5): scratching is found, everyday motion
/// is ignored, faster scratching reads as a higher rate, and answers teach the personal model.
@Suite struct DetectionTests {
    static let t0: TimeInterval = 780_000_000      // an arbitrary absolute time (2025)

    // MARK: - Helpers

    private func signal(_ build: (inout SyntheticMotion) -> Void) -> [MotionSample] {
        var b = SyntheticMotion(start: Self.t0)
        build(&b)
        return b.samples
    }

    private func run(_ build: (inout SyntheticMotion) -> Void, model: ScratchModel = ScratchModel(),
                     source: EpisodeSource = .live) -> [DetectorEvent] {
        let detector = ScratchDetector(model: model, source: source)
        return detector.process(signal(build)) + detector.finish()
    }

    private func seconds(_ date: Date) -> Double { date.timeIntervalSinceReferenceDate - Self.t0 }

    // MARK: - Scratching is detected

    @Test func scratchIsDetected() throws {
        let events = run { $0.still(6); $0.scratch(12, hz: 4); $0.still(6) }
        let episodes = events.episodes
        #expect(episodes.count == 1)
        let e = try #require(episodes.first).episode
        #expect(abs(seconds(e.start) - 6) <= 1.6, "starts when the scratching starts")
        #expect(abs(seconds(e.end) - 18) <= 1.6, "ends when it stops")
        #expect(abs(e.meanHz - 4) < 0.3)
        #expect(e.intense == false)
        #expect(e.source == .live)
        // The start is announced right away (to buzz), with the same id as the finished episode.
        let start = try #require(events.starts.first)
        #expect(events.starts.count == 1)
        #expect(start.shouldAlert)
        #expect(start.id == e.id)
        #expect(seconds(start.start) < 9, "announced within seconds, not at the end")
        #expect(start.windows.count == 2)
    }

    @Test func scratchWindowsScoreHigh() {
        let windows = run { $0.scratch(12, hz: 4.5) }.windows
        #expect(windows.count >= 6)
        #expect(windows.dropFirst().allSatisfy { $0.isScratch && $0.probability > 0.9 })
        #expect(windows.dropFirst().allSatisfy { $0.features.periodicity > 0.8 && $0.features.inBand > 0.7 })
    }

    @Test func gentleScratchStillCounts() {
        let episodes = run { $0.still(3); $0.scratch(10, hz: 3.5, amplitude: 0.08); $0.still(3) }.episodes
        #expect(episodes.count == 1)
    }

    // MARK: - Everyday motion is ignored

    @Test func walkingIsIgnored() {
        let swinging = run { $0.walk(30) }
        #expect(swinging.episodes.isEmpty)
        #expect(swinging.windows.allSatisfy { $0.features.moving && $0.probability < 0.5 })
        // Hands in pockets: the 1.8 Hz step rhythm is the main motion — rhythmic, but too slow.
        let pockets = run { $0.walk(30, armSwing: 0.04) }
        #expect(pockets.episodes.isEmpty)
        #expect(pockets.windows.allSatisfy { $0.probability < 0.5 })
    }

    @Test func typingIsIgnored() {
        let events = run { $0.type(30) }
        #expect(events.episodes.isEmpty)
        #expect(events.starts.isEmpty)
        #expect(events.windows.contains { $0.features.moving }, "typing passes the movement gate; the model rejects it")
        #expect(events.windows.allSatisfy { $0.probability < 0.5 })
    }

    @Test func stillIsIgnored() {
        let events = run { $0.still(30) }
        #expect(events.episodes.isEmpty)
        #expect(events.windows.count == 19)
        #expect(events.windows.allSatisfy { !$0.features.moving && $0.probability == 0 })
    }

    @Test func rollOverIsIgnored() {
        let events = run { $0.still(5); $0.rollOver(); $0.still(5) }
        #expect(events.episodes.isEmpty)
        #expect(events.windows.contains { $0.features.moving && $0.features.strength > 0.2 }, "a big movement…")
        #expect(events.windows.allSatisfy { $0.probability < 0.5 }, "…but not a rhythm")
    }

    @Test func nightMixFindsOnlyTheScratching() {
        let events = run {
            $0.still(10); $0.rollOver(); $0.still(8)
            $0.scratch(9, hz: 4.2); $0.still(12)
            $0.type(10); $0.walk(10); $0.still(6)
            $0.scratch(7, hz: 5.4, amplitude: 0.65); $0.still(6)
        }
        let episodes = events.episodes.map(\.episode)
        #expect(episodes.count == 2)
        #expect(episodes.first.map { abs(seconds($0.start) - 19.6) < 2 } == true)
        #expect(episodes.last?.intense == true)
    }

    // MARK: - Rate and intensity

    @Test func fasterScratchReadsHigherHz() {
        let rates = [2.8, 4.0, 5.2, 6.5].map { hz in
            run { $0.still(3); $0.scratch(9, hz: hz); $0.still(3) }.episodes.first?.episode.meanHz ?? 0
        }
        for (measured, truth) in zip(rates, [2.8, 4.0, 5.2, 6.5]) { #expect(abs(measured - truth) < 0.35) }
        #expect(rates == rates.sorted() && Set(rates).count == rates.count, "strictly increasing: \(rates)")
    }

    @Test func intenseNeedsStrongMotion() {
        let strong = run { $0.scratch(8, hz: 4, amplitude: 0.6) }.episodes.first?.episode
        let normal = run { $0.scratch(8, hz: 4, amplitude: 0.25) }.episodes.first?.episode
        #expect(strong?.intense == true)
        #expect((strong?.meanRMS ?? 0) >= 0.35)
        #expect(normal?.intense == false)
    }

    // MARK: - Episode logic

    private func window(_ i: Int, _ scratch: Bool) -> WindowResult {
        let f = WindowFeatures(start: Self.t0 + Double(i) * 1.5, axisSD: [0.2, 0.05, 0.05], strength: 0.2, moving: true, axis: 0,
                               dominantHz: 4, periodicity: scratch ? 0.95 : 0.1, inBand: scratch ? 0.9 : 0.1, crossingHz: 4,
                               logStrength: 1, crossingScore: 1)
        return WindowResult(features: f, probability: scratch ? 0.95 : 0.05, isScratch: scratch)
    }

    private func track(_ pattern: String) -> [DetectorEvent] {
        var tracker = EpisodeTracker(config: .standard, source: .live)
        var events: [DetectorEvent] = []
        for (i, c) in pattern.enumerated() { events += tracker.feed(window(i, c == "S")) }
        return events + tracker.finish()
    }

    @Test func episodeNeedsTwoScratchWindowsWithOneGapAllowed() throws {
        #expect(track("NNSNNN").episodes.isEmpty, "one lone window is not an episode")
        #expect(track("SNNSNN").episodes.isEmpty, "a 2-window gap breaks the run")
        #expect(track("SS").episodes.count == 1)
        let gap = track("NSNSNN")
        #expect(gap.episodes.count == 1, "a 1-window gap is allowed")
        let e = try #require(gap.episodes.first)
        #expect(e.windows.count == 2)
        // Trimmed by half a hop at both ends: windows 1 and 3 cover 1.5 s ... 4.5 + 3 s.
        #expect(abs(seconds(e.episode.start) - (1.5 + 0.75)) < 1e-6)
        #expect(abs(seconds(e.episode.end) - (4.5 + 3 - 0.75)) < 1e-6)
        let two = track("SSSNSSNNSS")
        #expect(two.episodes.count == 2)
        #expect(two.episodes.first?.windows.count == 5)
        #expect(two.starts.count == 2)
    }

    @Test func buzzesAtMostOncePer45Seconds() {
        let close = run { $0.scratch(6, hz: 4); $0.still(15); $0.scratch(6, hz: 4); $0.still(3) }
        #expect(close.episodes.count == 2)
        #expect(close.starts.map(\.shouldAlert) == [true, false])
        let apart = run { $0.scratch(6, hz: 4); $0.still(50); $0.scratch(6, hz: 4); $0.still(3) }
        #expect(apart.starts.map(\.shouldAlert) == [true, true])
    }

    @Test func holeInTheDataEndsTheEpisode() {
        var a = SyntheticMotion(start: Self.t0)
        a.scratch(8, hz: 4)
        var b = SyntheticMotion(start: a.time + 5, seed: 9)
        b.scratch(8, hz: 4)
        let detector = ScratchDetector()
        let events = detector.process(a.samples + b.samples) + detector.finish()
        #expect(events.episodes.count == 2)
    }

    @Test func streamingMatchesBatch() {
        let samples = signal { $0.still(4); $0.scratch(10, hz: 4.4); $0.walk(8); $0.scratch(6, hz: 3.3); $0.still(4) }
        let batch = ScratchDetector.episodes(in: samples, model: ScratchModel(), source: .recorded).map(\.episode)
        let streaming = ScratchDetector(source: .recorded)
        var events: [DetectorEvent] = []
        var i = 0
        while i < samples.count {                       // odd-sized chunks, like sensor callbacks
            let chunk = samples[i..<min(samples.count, i + 37)]
            events += streaming.process(chunk)
            i += 37
        }
        events += streaming.finish()
        let streamed = events.episodes.map(\.episode)
        #expect(batch.count == 2)
        #expect(streamed.map(\.start) == batch.map(\.start))
        #expect(streamed.map(\.end) == batch.map(\.end))
        #expect(batch.allSatisfy { $0.source == .recorded })
    }

    // MARK: - Learning from Yes / No

    private func borderline() -> [WindowFeatures] {
        run { $0.scratch(9, hz: 2.6, amplitude: 0.05) }.windows.map(\.features).filter(\.moving)
    }

    private func meanP(_ m: ScratchModel, _ ws: [WindowFeatures]) -> Double {
        ws.map(m.probability).reduce(0, +) / Double(ws.count)
    }

    @Test func answersMoveTheProbability() {
        let windows = borderline()
        #expect(!windows.isEmpty)
        var m = ScratchModel()
        let start = meanP(m, windows)
        #expect(start > 0.3 && start < 0.95, "a borderline pattern: \(start)")
        m.learn(from: windows, scratching: false)
        let afterNo = meanP(m, windows)
        #expect(afterNo < start, "No lowers it: \(start) → \(afterNo)")
        m.learn(from: windows, scratching: true)
        m.learn(from: windows, scratching: true)
        let afterYes = meanP(m, windows)
        #expect(afterYes > afterNo, "Yes raises it: \(afterNo) → \(afterYes)")
        #expect(m.confirmedCount == 2 && m.rejectedCount == 1 && m.answerCount == 3)
        #expect(m.updatedAt != nil)
    }

    @Test func repeatedNoTeachesTheWatchToIgnoreAPattern() {
        let windows = borderline()
        var m = ScratchModel()
        #expect(run({ $0.scratch(9, hz: 2.6, amplitude: 0.05) }, model: m).episodes.count == 1)
        for _ in 0..<4 { m.learn(from: windows, scratching: false) }
        #expect(run({ $0.scratch(9, hz: 2.6, amplitude: 0.05) }, model: m).episodes.isEmpty, "that gentle pattern is now ignored")
        #expect(run({ $0.scratch(9, hz: 4.5, amplitude: 0.3) }, model: m).episodes.count == 1, "real scratching still counts")
    }

    @Test func modelSurvivesJSONAndResets() throws {
        var m = ScratchModel()
        m.learn(from: borderline(), scratching: true)
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(ScratchModel.self, from: data)
        #expect(back == m)
        #expect(back.weights != ScratchModel.startingWeights)
        var r = back
        r.reset()
        #expect(r.weights == ScratchModel.startingWeights && r.answerCount == 0)
    }

    @Test func stillWindowsNeverScore() {
        let f = FeatureExtractor().features(x: .init(repeating: 0.1, count: 150), y: .init(repeating: -0.2, count: 150),
                                            z: .init(repeating: -0.97, count: 150), start: 0)
        #expect(!f.moving && ScratchModel().probability(f) == 0)
    }

    @Test func crossingScoreShape() {
        #expect(FeatureExtractor.crossingScore(1) == 0)
        #expect(FeatureExtractor.crossingScore(4) == 1)
        #expect(FeatureExtractor.crossingScore(13) == 0)
        #expect(FeatureExtractor.crossingScore(2) > 0 && FeatureExtractor.crossingScore(2) < 1)
    }

    // MARK: - Episodes travel to the phone as JSON (contract: default JSONEncoder)

    @Test func episodesRoundTripWithDefaultCoders() throws {
        let episodes = run { $0.scratch(8, hz: 4) }.episodes.map(\.episode)
        let data = try JSONEncoder().encode(episodes)
        let back = try JSONDecoder().decode([ScratchEpisode].self, from: data)
        #expect(back == episodes)
    }
}
