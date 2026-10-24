import SwiftUI
import EczemaKit

/// No test running: explain the test Claude suggested, with a big start button.
struct SuggestedExperimentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var caseFile: CaseFile?

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onAppear { ScrollHook.scrollIfAsked(proxy, after: 1.5) }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Twin.Space.m) {
            if let caseFile, let plan = StoryTravel.plan(for: caseFile, in: app.dataset) {
                hero(plan)
                    .entranceRise(0.04)
                if let why = caseFile.cannotSeparate.first {
                    WhyTestCard(text: why, suspects: Array(caseFile.suspects.prefix(2)))
                        .entranceRise(0.04 + Twin.Motion.stagger)
                }
                HowItWorksCard(plan: plan)
                    .entranceRise(0.04 + 2 * Twin.Motion.stagger)
            } else {
                noPlan.entranceRise(0.04)
            }
            Color.clear.frame(height: 1).id(ScrollHook.bottomID)
        }
        .onAppear { ExperimentSession.shared.celebrated = false }
    }

    private func hero(_ plan: ExperimentPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "flask.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 36, height: 36)
                    .sticker(Twin.Palette.cyan)
                Eyebrow(text: "Claude suggests a test")
            }
            Text("\(plan.title) for \(plan.lengthDays) days")
                .font(Twin.Typeface.sans(28, .bold))
                .tracking(-0.6)
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(plan.instruction)
                .font(Twin.Typeface.sans(15))
                .foregroundStyle(Twin.Palette.inkMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            PreviewTiles(length: plan.lengthDays, animate: !reduceMotion)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

            Button { StoryTravel.startExperiment(app: app) } label: {
                HStack(spacing: 8) {
                    Text("Start the \(plan.lengthDays)-day test")
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                }
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink, height: 56))
        }
        .twinCard()
    }

    private var noPlan: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "flask")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 40, height: 40)
                .sticker(Twin.Palette.cyan)
            Text("No test yet").font(Twin.Typeface.title).foregroundStyle(Twin.Palette.ink)
            Text("When Claude finds a likely trigger, it suggests one small change to try for 10 days. Your watch measures the difference.")
                .font(Twin.Typeface.sans(15))
                .foregroundStyle(Twin.Palette.inkMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button { app.select(.insight) } label: {
                HStack(spacing: 8) {
                    Text("See Claude’s analysis")
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                }
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.paper))
        }
        .twinCard()
    }
}

/// Ten empty day tiles that pop in one after another: what the test will look like.
private struct PreviewTiles: View {
    var length: Int
    var animate: Bool
    @State private var shown = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...max(length, 1), id: \.self) { d in
                Text("\(d)")
                    .font(Twin.Typeface.mono(d >= 10 ? 9 : 10, bold: true))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 26, height: 26)
                    .sticker(d == 1 ? Twin.Palette.yellow : Twin.Palette.paper)
                    .scaleEffect(d <= shown ? 1 : 0.5)
                    .opacity(d <= shown ? 1 : 0)
            }
        }
        .onAppear {
            guard animate else { shown = length; return }
            for d in 1...max(length, 1) {
                withAnimation(Twin.Motion.bouncy.delay(0.25 + Double(d) * 0.045)) { shown = max(shown, d) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(length) days")
    }
}

/// Why a test: the two suspects that started together.
private struct WhyTestCard: View {
    var text: String
    var suspects: [Suspect]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Why a test")
            if suspects.count == 2 {
                HStack(spacing: 8) {
                    Sticker(text: suspects[0].title, icon: suspects[0].kind?.emoji, fill: Twin.Palette.pink)
                    Text("or").font(Twin.Typeface.sans(13)).foregroundStyle(Twin.Palette.inkMuted)
                    Sticker(text: suspects[1].title, icon: suspects[1].kind?.emoji, fill: Twin.Palette.orange)
                }
            }
            Text(text + " Changing one thing at a time tells them apart.")
                .font(Twin.Typeface.sans(14))
                .foregroundStyle(Twin.Palette.inkMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .twinCard(fill: Twin.Palette.cream)
    }
}

/// Three numbered steps.
private struct HowItWorksCard: View {
    var plan: ExperimentPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "How it works")
            step(1, firstSentence(plan.instruction))
            step(2, "Wear your watch as usual. It counts the scratching for you, day and night.")
            step(3, "On day \(plan.lengthDays) you’ll know if the \(plan.subject ?? "change") is a trigger for you.")
        }
        .twinCard()
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(Twin.Typeface.mono(11, bold: true))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 24, height: 24)
                .sticker(Twin.Palette.yellow)
            Text(text)
                .font(Twin.Typeface.sans(15))
                .foregroundStyle(Twin.Palette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func firstSentence(_ s: String) -> String {
        guard let r = s.range(of: ". ") else { return s }
        return String(s[..<r.lowerBound]) + "."
    }
}
