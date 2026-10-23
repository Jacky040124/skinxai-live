import SwiftUI
import EczemaKit

/// Digital Crown page 2: the latest episodes, newest first, grouped by day.
/// Each row: time, length, a bar for how long it lasted, its rate, and a flame when intense.
struct RecentScreen: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        let days = model.recentDays()
        let longest = max(30, days.flatMap(\.episodes).map(\.duration).max() ?? 60)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                if days.isEmpty {
                    EmptyRecent()
                }
                ForEach(Array(days.enumerated()), id: \.element.id) { dayIndex, day in
                    DayHeader(day: day.day, minutes: model.minutes(on: day.day))
                        .padding(.top, dayIndex == 0 ? 0 : 8)
                    ForEach(Array(day.episodes.enumerated()), id: \.element.id) { i, e in
                        EpisodeRow(episode: e, longest: longest, delay: rowDelay(day: dayIndex, row: i, days: days))
                    }
                }
                Footer(isDemo: !model.usesRealData, learned: model.answersLearned)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }

    /// Rows rise in one after another (first screenful only).
    private func rowDelay(day: Int, row: Int, days: [EpisodeDay]) -> Double {
        let before = days.prefix(day).reduce(0) { $0 + $1.episodes.count + 1 }
        return Double(min(before + row + day + 1, 8)) * Twin.Motion.stagger
    }
}

private struct DayHeader: View {
    var day: Date
    var minutes: Double
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(WatchFont.mono(10, bold: true))
                .tracking(0.6)
                .foregroundStyle(Twin.Palette.nightMuted)
            Spacer()
            Text("\(Int(minutes.rounded())) MIN")
                .font(WatchFont.mono(10))
                .foregroundStyle(Twin.Palette.nightMuted)
        }
        .padding(.horizontal, 6)
        .accessibilityAddTraits(.isHeader)
    }

    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

private struct EpisodeRow: View {
    var episode: ScratchEpisode
    var longest: TimeInterval
    var delay: Double
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(episode.start, format: .dateTime.hour().minute())
                    .font(WatchFont.mono(13, bold: true))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(Self.length(episode.duration))
                    .font(WatchFont.sans(15, .bold))
                    .foregroundStyle(.white)
                if episode.intense {
                    WatchTile(symbol: "flame.fill", fill: Twin.Palette.orange, size: 17)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                }
            }
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Twin.Palette.nightTrack)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(episode.intense ? Twin.Palette.orange : Color.white.opacity(0.75))
                            .frame(width: geo.size.width * (grown ? fraction : 0))
                    }
                }
                .frame(height: 4)
                Text(String(format: "%.1f HZ", episode.meanHz))
                    .font(WatchFont.mono(9.5))
                    .foregroundStyle(Twin.Palette.nightMuted)
                    .fixedSize()
                    .frame(height: 9)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 5)
        .padding(.bottom, 8)
        .background(Twin.Palette.nightCard, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .riseIn(delay, distance: 10)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Twin.Motion.fill.delay(delay + 0.1)) { grown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var fraction: Double { min(1, max(0.06, episode.duration / longest)) }

    private var accessibilityText: String {
        let time = episode.start.formatted(.dateTime.hour().minute())
        return "\(time), \(Self.length(episode.duration))\(episode.intense ? ", intense" : "")"
    }

    static func length(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        let m = s / 60, r = s % 60
        return r == 0 ? "\(m)m" : "\(m)m \(r)s"
    }
}

private struct Footer: View {
    var isDemo: Bool
    var learned: Int
    var body: some View {
        VStack(spacing: 4) {
            if learned > 0 {
                Text("Learned from \(learned) \(learned == 1 ? "answer" : "answers")")
                    .font(WatchFont.sans(12, .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(isDemo ? "DEMO STORY · YOUR OWN DATA REPLACES IT" : "SENT TO YOUR IPHONE")
                .font(WatchFont.mono(8.5))
                .tracking(0.3)
                .foregroundStyle(Twin.Palette.nightMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }
}

private struct EmptyRecent: View {
    var body: some View {
        VStack(spacing: 6) {
            WatchTile(symbol: "hand.raised.fill", fill: Twin.Palette.lime, size: 28)
            Text("No scratching yet today")
                .font(WatchFont.sans(15, .bold))
                .foregroundStyle(.white)
            Text("Episodes show up here as your watch finds them.")
                .font(WatchFont.sans(12))
                .foregroundStyle(Twin.Palette.nightMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
