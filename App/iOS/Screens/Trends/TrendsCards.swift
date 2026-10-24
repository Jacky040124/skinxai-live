import SwiftUI
import EczemaKit

// MARK: - Detail strip of the selected day

/// Cyan strip under the chart ("this item"): the selected day's numbers. Numbers roll when the
/// selection moves; until the first tap it shows a "tap a day" hint.
struct TrendsDayDetail: View {
    let snap: TrendsSnapshot
    let index: Int
    let showHint: Bool

    var body: some View {
        let d = snap.days[index]
        let ds = snap.dataset
        let started = snap.changes.filter { $0.startIndex == index }
        // Real data: only what was measured (0 h / 0 ms / 0% = nothing came in that day).
        let sleep = TodayTrends.sleep(d, in: ds)
        let hrv = TodayTrends.hrv(d, in: ds)
        let humidity = TodayTrends.humidity(d, in: ds)
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Text(eyebrow(d))
                    .font(Twin.Typeface.eyebrow).tracking(0.8)
                    .foregroundStyle(Twin.Palette.cyanStrong)
                    .contentTransition(.interpolate)
                Spacer(minLength: 4)
                if showHint {
                    Sticker(text: "tap a day", icon: "hand.tap.fill", fill: Twin.Palette.paper)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else if snap.tracked[index] {
                    toneSticker(snap.tones[index])
                        .id(snap.tones[index])
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(Int(d.scratchMinutes.rounded()))")
                    .font(Twin.Typeface.sans(28, .bold)).tracking(-1)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: d.scratchMinutes))
                Text(" min").font(Twin.Typeface.sans(16, .bold))
                Text(" · " + worstText(d))
                    .font(Twin.Typeface.sans(15))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .contentTransition(.interpolate)
            }
            .foregroundStyle(Twin.Palette.ink)
            HStack(spacing: 14) {
                if sleep == nil, hrv == nil, humidity == nil {
                    Text("No sleep, HRV or weather data")
                        .font(Twin.Typeface.sans(13))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                if let sleep { metric("moon.zzz.fill", String(format: "%.1f h", sleep)) }
                if let hrv { metric("waveform.path.ecg", "\(Int(hrv.rounded())) ms") }
                if let humidity { metric("humidity.fill", "\(Int(humidity.rounded()))%") }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    ForEach(d.exposures.prefix(4)) { e in
                        Text(e.kind.emoji).font(.system(size: 11))
                            .frame(width: 22, height: 22)
                            .sticker(fill(for: e))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            if let (n, length) = testDay, !started.contains(where: \.isTest) {
                HStack(spacing: 8) {
                    Text("🧪").font(.system(size: 11)).frame(width: 22, height: 22).sticker(Twin.Palette.cyan)
                    Text("Test day \(n) of \(length)")
                        .font(Twin.Typeface.sans(13, .bold))
                        .foregroundStyle(Twin.Palette.ink)
                        .contentTransition(.numericText())
                }
            }
            ForEach(started) { c in
                HStack(spacing: 8) {
                    Text(c.emoji).font(.system(size: 11)).frame(width: 22, height: 22).sticker(c.fill)
                    Text(c.isTest ? "Test day 1: \(c.title.lowercased())" : "\(c.title) started")
                        .font(Twin.Typeface.sans(13, .bold))
                        .foregroundStyle(Twin.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Twin.Palette.cyanSoft, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
        .accessibilityElement(children: .combine)
    }

    private func eyebrow(_ d: DayRecord) -> String {
        var parts = [TodayTrends.Format.weekdayDay(d.day)]
        if index == snap.days.count - 1 { parts.append("TODAY") }
        return parts.joined(separator: " · ")
    }

    /// (day, length) when this day is part of the user's test.
    private var testDay: (Int, Int)? {
        guard let test = snap.dataset.experiment,
              let start = snap.days.firstIndex(where: { Calendar.current.isDate($0.day, inSameDayAs: test.startDay) }),
              index >= start else { return nil }
        return (index - start + 1, test.plan.lengthDays)
    }

    private func worstText(_ d: DayRecord) -> String {
        // Real data: a day without episodes may be a day the watch was off, so no "calm" claim.
        guard let h = d.worstHour else { return snap.tracked[index] ? "calm all day" : "no episodes" }
        return "worst at \(TodayTrends.Format.hour(h))"
    }

    private func toneSticker(_ tone: DailyScratchChart.Tone) -> some View {
        switch tone {
        case .flare: Sticker(text: "flare", icon: "flame.fill", fill: Twin.Palette.orange)
        case .improving: Sticker(text: "improving", icon: "arrow.down.right", fill: Twin.Palette.lime)
        case .normal: Sticker(text: "normal", icon: "checkmark", fill: Twin.Palette.paper)
        }
    }

    private func metric(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Twin.Palette.inkMuted)
            Text(text)
                .font(Twin.Typeface.mono(12))
                .foregroundStyle(Twin.Palette.ink)
                .contentTransition(.numericText())
        }
    }

    private func fill(for e: Exposure) -> Color {
        snap.changes.first { !$0.isTest && $0.kind == e.kind && $0.title == e.title }?.fill ?? Twin.Palette.paper
    }
}

// MARK: - What changed

struct TrendsChangesCard: View {
    let changes: [TrendsChange]
    let routine: [TrendsRoutine]
    let days: [DayRecord]
    let onSelect: (TrendsChange) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "What changed")
            VStack(spacing: 0) {
                ForEach(changes) { c in
                    Button { onSelect(c) } label: { row(c) }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint("Shows that day on the chart")
                    if c.id != changes.last?.id {
                        Rectangle().fill(Twin.Palette.hairline).frame(height: 1).padding(.leading, 46)
                    }
                }
            }
            if !routine.isEmpty {
                HStack(alignment: .center, spacing: 10) {
                    Text("Also logged")
                        .font(Twin.Typeface.sans(13))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .fixedSize()
                    StickerWrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(routine) { r in
                            TodayEmojiSticker(emoji: r.emoji, text: "\(r.count)×", fill: Twin.Palette.paper)
                                .accessibilityLabel("\(r.title), \(r.count) times")
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .twinCard()
    }

    private func row(_ c: TrendsChange) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(c.emoji)
                .font(.system(size: 16))
                .frame(width: 34, height: 34)
                .sticker(c.fill)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title)
                    .font(Twin.Typeface.sans(15, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(c.detail)
                    .font(Twin.Typeface.sans(13))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                Text(dateText(c))
                    .font(Twin.Typeface.mono(11))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .multilineTextAlignment(.trailing)
                if c.paused {
                    Sticker(text: "paused", icon: "pause.fill", fill: Twin.Palette.lime)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func dateText(_ c: TrendsChange) -> String {
        let a = days[c.startIndex].day
        if c.ongoing { return "SINCE\n\(TodayTrends.Format.day(a).uppercased())" }
        return TodayTrends.Format.dayRange(a, days[c.endIndex].day).uppercased()
    }
}

// MARK: - Sleep & stress

/// Sleep and HRV over the same days as the chart (points line up with the bars); flare days
/// are shaded and the selected day is marked in cyan. Days without a Health value are gaps in
/// the line (real data); with no value at all the card says what is missing and how to connect.
struct TrendsBodyCard: View {
    let snap: TrendsSnapshot
    let selectedIndex: Int?
    /// "Allow Health" chip (Health not asked yet).
    var canAskHealth = false
    /// Opens Settings (Apple Health). nil = the empty state is not tappable.
    var onConnect: (() -> Void)? = nil

    var body: some View {
        let ds = snap.dataset
        let days = Array(snap.visible)
        let sleep = days.map { TodayTrends.sleep($0, in: ds) }
        let hrv = days.map { TodayTrends.hrv($0, in: ds) }
        if sleep.allSatisfy({ $0 == nil }) && hrv.allSatisfy({ $0 == nil }) {
            empty
        } else {
            charts(sleep: sleep, hrv: hrv)
        }
    }

    private func charts(sleep: [Double?], hrv: [Double?]) -> some View {
        let ds = snap.dataset
        let sel = selectedIndex.map { $0 - snap.visibleStart }
        let flares = snap.visibleRange.map { snap.tones[$0] == .flare }
        let selected = selectedIndex.map { snap.days[$0] }
        let hasUsual = snap.usualSleep != nil || snap.usualHRV != nil
        return VStack(alignment: .leading, spacing: 18) {
            signal(title: "Sleep",
                   value: selected.flatMap { TodayTrends.sleep($0, in: ds) }.map { String(format: "%.1f h", $0) },
                   usual: snap.usualSleep.map { String(format: "usual %.1f h", $0) },
                   values: sleep, missing: "No sleep data on these days",
                   chart: SignalLineChart(values: sleep, usual: snap.usualSleep, shaded: flares,
                                          selectedIndex: sel, height: 54, delay: 0.45))
            signal(title: "Stress (HRV)",
                   value: selected.flatMap { TodayTrends.hrv($0, in: ds) }.map { "\(Int($0.rounded())) ms" },
                   usual: snap.usualHRV.map { "usual \(Int($0.rounded())) ms" },
                   values: hrv, missing: "No HRV data on these days",
                   chart: SignalLineChart(values: hrv, usual: snap.usualHRV, shaded: flares,
                                          selectedIndex: sel, height: 54, delay: 0.6))
            if flares.contains(true) || hasUsual {
                HStack(spacing: 14) {
                    if flares.contains(true) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(Twin.Palette.orangeSoft)
                                .frame(width: 12, height: 10)
                            Text("flare days")
                        }
                    }
                    if hasUsual {
                        HStack(spacing: 5) {
                            ChartHLine().stroke(Twin.Palette.ink.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(width: 16, height: 2)
                            Text("your usual")
                        }
                    }
                }
                .font(Twin.Typeface.mono(10))
                .foregroundStyle(Twin.Palette.inkHint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .twinCard()
    }

    /// `value` nil = the selected day has no measurement.
    private func signal(title: String, value: String?, usual: String?, values: [Double?], missing: String,
                        chart: SignalLineChart) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Eyebrow(text: title)
                Spacer(minLength: 4)
                if let usual {
                    Text(usual).font(Twin.Typeface.mono(11)).foregroundStyle(Twin.Palette.inkHint)
                }
                Text(value ?? TodayTrends.Format.noValue)
                    .font(Twin.Typeface.sans(16, .bold))
                    .foregroundStyle(value == nil ? Twin.Palette.inkHint : Twin.Palette.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            if values.contains(where: { $0 != nil }) {
                chart
            } else {
                // Same height as a chart, so the card keeps its rhythm.
                ZStack {
                    ChartHLine()
                        .stroke(Twin.Palette.hairline, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1.5, 4]))
                        .frame(height: 2)
                    Text(missing)
                        .font(Twin.Typeface.sans(13))
                        .foregroundStyle(Twin.Palette.inkHint)
                        .padding(.horizontal, 8)
                        .background(Twin.Palette.paper)
                }
                .frame(height: 54)
            }
        }
    }

    /// No Health value in the whole range (real data before Apple Health is connected).
    @ViewBuilder private var empty: some View {
        let content = HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 36, height: 36)
                .sticker(Twin.Palette.cream)
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: "Sleep & stress")
                Text("Sleep and HRV from Apple Health show up here, day by day under your scratching.")
                    .font(Twin.Typeface.sans(13))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if canAskHealth {
                    TodayConnectChip(symbol: "heart.fill", text: "Allow Health")
                        .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .twinCard()
        .contentShape(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        if let onConnect {
            Button(action: onConnect) { content }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Opens Settings")
        } else {
            content
        }
    }
}

// MARK: - Screenshot / demo hook

extension TodayTrends {
    /// `-scrollTo bottom` (screenshots, demo recordings): scroll the tab to its end after the entrance.
    static func scrollForScreenshot(_ proxy: ScrollViewProxy, bottomID: String) {
        guard UserDefaults.standard.string(forKey: "scrollTo") == "bottom" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(Twin.Motion.slide) { proxy.scrollTo(bottomID, anchor: .top) }
        }
    }
}
