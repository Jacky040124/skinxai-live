import SwiftUI
import EczemaKit

/// Digital Crown page 2: the latest episodes, newest first, grouped by day.
/// Each row: time, length, a bar for how long it lasted, its rate, and a flame when intense.
struct RecentScreen: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        let override = UserDefaults.standard.integer(forKey: "recentLimit")   // `-recentLimit N` (screenshots)
        let days = model.recentDays(limit: override > 0 ? override : 24)
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
                StatusCard()
                    .padding(.top, 10)
                    .watchRise(0.5, distance: 10)
                if !model.usesRealData {
                    Text("DEMO STORY · YOUR OWN DATA REPLACES IT")
                        .font(WatchFont.mono(8.5))
                        .tracking(0.3)
                        .foregroundStyle(Twin.Palette.nightMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .padding(.horizontal, 8)
                }
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
        .watchRise(delay, distance: 10)
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

/// What the watch knows about itself: how much it learned from you (with a reset), the all-day
/// recorder, and the last hand-off to the iPhone.
private struct StatusCard: View {
    @EnvironmentObject var model: WatchModel
    @State private var confirmReset = false

    var body: some View {
        let m = model.personal
        VStack(alignment: .leading, spacing: 10) {
            StatusLine(symbol: "sparkles", fill: Twin.Palette.cyan, title: "Learning from you",
                       detail: m.answerCount == 0 ? "ANSWER AN ALERT TO TEACH IT"
                                                  : "\(m.answerCount) \(m.answerCount == 1 ? "ANSWER" : "ANSWERS") · \(m.confirmedCount) YES · \(m.rejectedCount) NO")
            if case let .on(_, backing) = model.live {
                StatusLine(symbol: "waveform", fill: Twin.Palette.cyan, title: "Live detection", detail: Self.detail(backing))
            }
            switch model.recorderStatus {
            case .unavailable:
                EmptyView()
            case .denied:
                StatusLine(symbol: "exclamationmark", fill: Twin.Palette.red, title: "All-day recording",
                           detail: "MOTION ACCESS IS OFF")
            case .off:
                StatusLine(symbol: "pause.fill", fill: Twin.Palette.nightTrack, title: "All-day recording",
                           detail: "OPEN TWIN TO RESTART IT")
            case let .on(until):
                StatusLine(symbol: "record.circle", fill: Twin.Palette.lime, title: "All-day recording",
                           detail: "ON UNTIL " + until.formatted(.dateTime.hour().minute()).uppercased())
            }
            if let sent = model.lastSentAt {
                StatusLine(symbol: "iphone", fill: Twin.Palette.yellow, title: "On your iPhone",
                           detail: "SENT " + sent.formatted(.dateTime.hour().minute()).uppercased())
            } else if model.waitingForPhone > 0 {
                StatusLine(symbol: "iphone", fill: Twin.Palette.nightTrack, title: "iPhone",
                           detail: "\(model.waitingForPhone) WAITING TO SEND")
            }
            if m.answerCount > 0 {
                Button("Reset learning") { confirmReset = true }
                    .buttonStyle(WatchButtonStyle(fill: Twin.Palette.nightTrack, foreground: .white, height: 30, radius: 9,
                                                  fontSize: 13))
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Twin.Palette.nightCard, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .confirmationDialog("Forget what Twin learned?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { model.resetLearning() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Detection goes back to its starting settings.")
        }
    }
}

extension StatusCard {
    /// What keeps live detection running, in plain words.
    static func detail(_ backing: LiveMonitor.Backing) -> String {
        switch backing {
        case .workout: "WORKOUT SESSION · WORKS WITH THE SCREEN OFF"
        case .extendedRuntime: "RUNS UP TO AN HOUR IN THE BACKGROUND"
        case .foreground: "ONLY WHILE TWIN IS ON SCREEN"
        case .simulated: "SIMULATED WRIST · NO SENSOR IN THE SIMULATOR"
        }
    }
}

private struct StatusLine: View {
    var symbol: String
    var fill: Color
    var title: String
    var detail: String
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            WatchTile(symbol: symbol, fill: fill, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(WatchFont.sans(13, .bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(WatchFont.mono(8.5))
                    .foregroundStyle(Twin.Palette.nightMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
