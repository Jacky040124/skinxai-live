import Foundation

/// Personal logistic model: P(scratching | window features).
///
/// Starts from hand-set weights and learns online from the user's Yes/No answers to
/// "Were you scratching?" (one small gradient step per answer, gently pulled back toward the
/// starting weights so a few odd answers cannot wreck it). Codable so the watch can keep it as JSON.
public struct ScratchModel: Codable, Hashable, Sendable {
    public static let featureNames = ["periodicity", "in-band 2.5–7 Hz", "log strength", "crossing rate"]
    /// Hand-set starting weights: [bias, periodicity, in-band, log strength, crossing score].
    public static let startingWeights: [Double] = [-8.0, 4.0, 7.0, 1.0, 1.5]

    /// [bias, w_periodicity, w_inBand, w_logStrength, w_crossing]
    public var weights: [Double]
    /// Answers the model has learned from.
    public var confirmedCount: Int
    public var rejectedCount: Int
    public var updatedAt: Date?
    public var learningRate: Double
    /// Pull toward the starting weights on every update (L2 to the prior).
    public var priorPull: Double

    public init(weights: [Double] = ScratchModel.startingWeights, learningRate: Double = 0.3, priorPull: Double = 0.02) {
        precondition(weights.count == Self.featureNames.count + 1, "bias + one weight per feature")
        self.weights = weights
        self.confirmedCount = 0
        self.rejectedCount = 0
        self.updatedAt = nil
        self.learningRate = learningRate
        self.priorPull = priorPull
    }

    public var answerCount: Int { confirmedCount + rejectedCount }

    /// 0...1. Windows that did not pass the movement gate are never scratching.
    public func probability(_ f: WindowFeatures) -> Double {
        guard f.moving else { return 0 }
        return probability(inputs: f.inputs)
    }

    public func probability(inputs x: [Double]) -> Double {
        var z = weights[0]
        for (i, v) in x.enumerated() where i + 1 < weights.count { z += weights[i + 1] * v }
        return 1 / (1 + exp(-z))
    }

    /// One online step of logistic regression on the episode's windows (gradient averaged over them).
    public mutating func learn(from windows: [WindowFeatures], scratching: Bool, at date: Date = Date()) {
        let moving = windows.filter(\.moving)
        guard !moving.isEmpty else { return }
        let y: Double = scratching ? 1 : 0
        var gradient = [Double](repeating: 0, count: weights.count)
        for w in moving {
            let x = [1] + w.inputs
            let err = y - probability(inputs: w.inputs)
            for j in 0..<gradient.count { gradient[j] += err * x[j] }
        }
        let m = Double(moving.count)
        for j in 0..<weights.count {
            let prior = Self.startingWeights[j]
            weights[j] += learningRate * (gradient[j] / m) - learningRate * priorPull * (weights[j] - prior)
        }
        if scratching { confirmedCount += 1 } else { rejectedCount += 1 }
        updatedAt = date
    }

    /// Back to the hand-set starting weights.
    public mutating func reset() {
        self = ScratchModel(learningRate: learningRate, priorPull: priorPull)
    }
}
