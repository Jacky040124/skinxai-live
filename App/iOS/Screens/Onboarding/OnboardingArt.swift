import SwiftUI
import EczemaKit

// MARK: - Page 1: the watch writes the diary

/// A watch built from shapes. It scratches (shakes, motion marks), and each scratch becomes a
/// diary note that flies out of it: today's real episodes, while the ring counts up to today's
/// minutes. Runs once each time the page becomes active.
struct WatchDiaryArt: View {
    var active: Bool
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Note: Identifiable, Equatable {
        let id: UUID
        let start: Date
        let minutes: Double
        let intense: Bool
    }

    @State private var notes: [Note] = []
    @State private var count: Double = 0
    @State private var scratch = 0
    @State private var run = 0

    private var today: DayRecord? { app.dataset.today }
    private var usual: Double { max(1, app.dataset.baselineMinutesPerDay) }

    /// Today's three longest episodes (mostly last night), oldest first.
    private var source: [Note] {
        guard let day = today?.day else { return [] }
        let todays = app.dataset.episodes.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
        return todays.sorted { $0.duration > $1.duration }.prefix(3).sorted { $0.start < $1.start }
            .map { Note(id: $0.id, start: $0.start, minutes: $0.duration / 60, intense: $0.intense) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            watch
                .keyframeAnimator(initialValue: WatchShake(), trigger: scratch) { view, s in
                    view.offset(x: reduceMotion ? 0 : s.x).rotationEffect(.degrees(reduceMotion ? 0 : s.angle))
                } keyframes: { _ in
                    KeyframeTrack(\.x) {
                        LinearKeyframe(-7, duration: 0.07)
                        LinearKeyframe(7, duration: 0.07)
                        LinearKeyframe(-6, duration: 0.07)
                        LinearKeyframe(6, duration: 0.07)
                        LinearKeyframe(-5, duration: 0.07)
                        LinearKeyframe(5, duration: 0.07)
                        LinearKeyframe(-3, duration: 0.07)
                        LinearKeyframe(0, duration: 0.07)
                    }
                    KeyframeTrack(\.angle) {
                        LinearKeyframe(-3, duration: 0.07)
                        LinearKeyframe(3, duration: 0.07)
                        LinearKeyframe(-2.5, duration: 0.07)
                        LinearKeyframe(2.5, duration: 0.07)
                        LinearKeyframe(-2, duration: 0.07)
                        LinearKeyframe(2, duration: 0.07)
                        LinearKeyframe(-1, duration: 0.07)
                        LinearKeyframe(0, duration: 0.07)
                    }
                }
                .overlay { ScratchMarks(trigger: scratch) }

            VStack(alignment: .leading, spacing: 8) {
                Text("SCRATCH DIARY")
                    .font(Twin.Typeface.mono(10, bold: true))
                    .tracking(0.8)
                    .foregroundStyle(Twin.Palette.frameInk)
                // Three diary lines: dashed until a scratch fills them, oldest first.
                ForEach(0..<max(3, source.count), id: \.self) { i in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Twin.Radius.sticker, style: .continuous)
                            .strokeBorder(Twin.Palette.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                            .frame(width: DiaryNote.width, height: 31)
                        if i < notes.count {
                            DiaryNote(note: notes[i])
                                .transition(reduceMotion ? .opacity : .asymmetric(
                                    insertion: .offset(x: -120, y: 0).combined(with: .scale(scale: 0.3, anchor: .leading)).combined(with: .opacity),
                                    removal: .opacity))
                        }
                    }
                }
            }
            .frame(width: DiaryNote.width + 4, alignment: .leading)
            .frame(height: 220, alignment: .center)
        }
        .onChange(of: active, initial: true) { _, isActive in
            if isActive { run += 1 }
        }
        .task(id: run) { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration: an Apple Watch notices scratching and writes each episode into a diary.")
    }

    private var watch: some View {
        let ratio = count / usual
        return ZStack {
            // Band
            VStack(spacing: 160) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Twin.Palette.ink).frame(width: 88, height: 74)
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Twin.Palette.ink).frame(width: 88, height: 74)
            }
            // Crown and button
            RoundedRectangle(cornerRadius: 3).fill(Twin.Palette.ink)
                .frame(width: 10, height: 30).offset(x: 80, y: -26)
            RoundedRectangle(cornerRadius: 2).fill(Twin.Palette.ink)
                .frame(width: 7, height: 40).offset(x: 79, y: 22)
            // Case + screen
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(Twin.Palette.ink)
                .frame(width: 158, height: 186)
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color.black)
                .frame(width: 140, height: 168)
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Twin.Palette.nightTrack, lineWidth: 11)
                    Circle()
                        .trim(from: 0, to: min(1, count / (3 * usual)))
                        .stroke(ratio > 1.5 ? Twin.Palette.orange : Twin.Palette.lime, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        CountingText(value: count, font: Twin.Typeface.sans(30, .bold), color: .white)
                        Text("MIN TODAY").font(Twin.Typeface.mono(8)).foregroundStyle(Twin.Palette.nightMuted)
                    }
                }
                .frame(width: 98, height: 98)
            }
            Text("Twin")
                .font(Twin.Typeface.sans(11, .bold))
                .foregroundStyle(Twin.Palette.yellow)
                .offset(x: -34, y: -70)
        }
        .frame(width: 176, height: 330)
    }

    private func play() async {
        let script = source
        let total = today?.scratchMinutes ?? 0
        let start = max(0, total - script.reduce(0) { $0 + $1.minutes })
        notes = []
        count = 0
        guard active else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.6)) { count = total; notes = script }
            return
        }
        withAnimation(.easeOut(duration: 0.8).delay(0.1)) { count = start }
        try? await Task.sleep(nanoseconds: 650_000_000)
        for note in script {
            guard !Task.isCancelled, active else { return }
            scratch += 1
            Haptics.soft()
            try? await Task.sleep(nanoseconds: 560_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Twin.Motion.bouncy) { notes.append(note) }
            withAnimation(.easeOut(duration: 0.6)) { count += note.minutes }
            try? await Task.sleep(nanoseconds: 850_000_000)
        }
        withAnimation(.easeOut(duration: 0.4)) { count = total }
    }
}

private struct WatchShake {
    var x: Double = 0
    var angle: Double = 0
}

/// Comic motion marks on both sides of the watch: drawn in, then gone.
private struct ScratchMarks: View {
    var trigger: Int
    var body: some View {
        ZStack {
            mark.rotationEffect(.degrees(-18)).offset(x: -106, y: -46)
            mark.rotationEffect(.degrees(4)).offset(x: -114, y: 6)
            mark.rotationEffect(.degrees(22)).offset(x: -102, y: 56)
            mark.rotationEffect(.degrees(162)).offset(x: 108, y: -60)
            mark.rotationEffect(.degrees(184)).offset(x: 116, y: 60)
        }
        .keyframeAnimator(initialValue: MarkPhase(), trigger: trigger) { view, p in
            view.opacity(p.opacity).scaleEffect(p.scale)
        } keyframes: { _ in
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: 0.08)
                LinearKeyframe(1, duration: 0.42)
                LinearKeyframe(0, duration: 0.25)
            }
            KeyframeTrack(\.scale) {
                SpringKeyframe(1.08, duration: 0.25, spring: .bouncy)
                LinearKeyframe(1.0, duration: 0.5)
            }
        }
        .allowsHitTesting(false)
    }

    private var mark: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 6))
            p.addLine(to: CGPoint(x: 7, y: 0))
            p.addLine(to: CGPoint(x: 14, y: 12))
            p.addLine(to: CGPoint(x: 21, y: 0))
            p.addLine(to: CGPoint(x: 28, y: 6))
        }
        .stroke(Twin.Palette.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .frame(width: 28, height: 12)
    }
}

private struct MarkPhase {
    var opacity: Double = 0
    var scale: Double = 0.9
}

private struct DiaryNote: View {
    let note: WatchDiaryArt.Note?
    var body: some View {
        HStack(spacing: 6) {
            Text(note.map { Self.clock.string(from: $0.start) } ?? "00:00")
                .font(Twin.Typeface.mono(12, bold: true))
            Text(note.map(Self.length) ?? "1 min")
                .font(Twin.Typeface.sans(13, .semibold))
            if note?.intense == true {
                Image(systemName: "flame.fill").font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(Twin.Palette.ink)
        .padding(.horizontal, 9)
        .frame(width: Self.width, height: 31, alignment: .leading)
        .sticker(note?.intense == true ? Twin.Palette.orange : Twin.Palette.paper)
    }

    static let width: CGFloat = 126

    /// 24-hour "03:12" (machine time, mono).
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func length(_ n: WatchDiaryArt.Note) -> String {
        n.minutes < 1 ? "\(Int((n.minutes * 60).rounded())) s" : "\(Int(n.minutes.rounded())) min"
    }
}

// MARK: - Page 2: tracked for you

/// Stickers of what the app tracks by itself (today's real values) drop onto the page one by one.
struct AutoTrackedArt: View {
    var active: Bool
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = 0
    @State private var run = 0

    struct Tile: Identifiable {
        let id: Int
        let emoji: String
        let title: String
        let value: String
        let source: String
        let fill: Color
        let tilt: Double
    }

    private var tiles: [Tile] {
        let d = app.dataset.today
        let ratio = app.dataset.todayRatio
        func num(_ v: Double?, _ digits: Int = 0) -> String? {
            guard let v, v > 0 else { return nil }
            return v.formatted(.number.precision(.fractionLength(digits)))
        }
        let humidity = d?.humidityPct ?? 0
        return [
            Tile(id: 0, emoji: "✋", title: "Scratching", value: num(d?.scratchMinutes).map { "\($0) min" } ?? "—",
                 source: "WATCH", fill: ratio >= 1.5 ? Twin.Palette.orange : Twin.Palette.paper, tilt: -3),
            Tile(id: 1, emoji: "🌙", title: "Sleep", value: num(d?.sleepHours, 1).map { "\($0) h" } ?? "—",
                 source: "HEALTH", fill: Twin.Palette.paper, tilt: 2.5),
            Tile(id: 2, emoji: "💓", title: "Stress (HRV)", value: num(d?.hrvMs).map { "\($0) ms" } ?? "—",
                 source: "HEALTH", fill: Twin.Palette.paper, tilt: 1.5),
            Tile(id: 3, emoji: "💧", title: "Humidity", value: num(d?.humidityPct).map { "\($0)%" } ?? "—",
                 source: "WEATHER", fill: humidity > 0 && humidity < 35 ? Twin.Palette.orange : Twin.Palette.paper, tilt: -2),
            Tile(id: 4, emoji: "🌬️", title: "Air quality", value: (d?.aqi).flatMap { $0 > 0 ? "AQI \($0)" : nil } ?? "—",
                 source: "WEATHER", fill: Twin.Palette.paper, tilt: -1.5),
            Tile(id: 5, emoji: "🌼", title: "Pollen", value: d?.pollen.label ?? "—",
                 source: "WEATHER", fill: Twin.Palette.paper, tilt: 3),
            Tile(id: 6, emoji: "🌡", title: "Temperature", value: d.map { TwinUnits.temperature($0.tempC) } ?? "—",
                 source: "WEATHER", fill: Twin.Palette.paper, tilt: 2),
            Tile(id: 7, emoji: "＋", title: "You add the rest", value: "one tap",
                 source: "YOU", fill: Twin.Palette.pink, tilt: -2.5),
        ]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.fixed(168), spacing: 14), GridItem(.fixed(168), spacing: 14)], spacing: 14) {
            ForEach(tiles) { tile in
                AutoTile(tile: tile)
                    .rotationEffect(.degrees(landed > tile.id ? tile.tilt : 0))
                    .scaleEffect(landed > tile.id ? 1 : 1.25)
                    .offset(y: landed > tile.id || reduceMotion ? 0 : -46)
                    .opacity(landed > tile.id ? 1 : 0)
            }
        }
        .onChange(of: active, initial: true) { _, isActive in
            if isActive { run += 1 }
        }
        .task(id: run) { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tracked automatically: scratching from your watch; sleep and stress from Health; humidity, air quality, pollen and temperature from the weather. You add the rest with one tap.")
    }

    private func play() async {
        landed = 0
        guard active else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) { landed = tiles.count }
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        for i in 0..<tiles.count {
            guard !Task.isCancelled, active else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { landed = i + 1 }
            if i % 2 == 0 { Haptics.soft() }
            try? await Task.sleep(nanoseconds: 110_000_000)
        }
    }
}

private struct AutoTile: View {
    let tile: AutoTrackedArt.Tile
    var body: some View {
        HStack(spacing: 10) {
            Text(tile.emoji)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 34, height: 34)
                .sticker(Twin.Palette.cream)
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.title)
                    .font(Twin.Typeface.sans(13, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                HStack(alignment: .firstTextBaseline) {
                    Text(tile.value)
                        .font(Twin.Typeface.mono(12))
                        .foregroundStyle(Twin.Palette.ink.opacity(0.75))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(tile.source)
                        .font(Twin.Typeface.mono(8, bold: true))
                        .tracking(0.5)
                        .foregroundStyle(Twin.Palette.ink.opacity(0.5))
                }
            }
        }
        .padding(10)
        .frame(width: 168, height: 62)
        .sticker(tile.fill)
    }
}

// MARK: - Page 3: permissions

/// Real permission requests as cards on the frame: Apple Health, location, notifications, and the
/// watch pairing status.
struct PermissionCards: View {
    var active: Bool
    @EnvironmentObject var access: DeviceAccess
    @EnvironmentObject var watch: WatchInbox
    @State private var shown = false

    var body: some View {
        VStack(spacing: 10) {
            row(0, icon: "heart.fill", title: "Apple Health", detail: "Sleep, HRV, resting pulse", state: access.health,
                manage: access.openHealth) {
                Task { await access.requestHealth() }
            }
            row(1, icon: "location.fill", title: "Location", detail: "Air, humidity, pollen near you", state: access.location) {
                access.requestLocation()
            }
            row(2, icon: "bell.fill", title: "Notifications", detail: "A heads-up when a flare starts", state: access.notifications) {
                Task { await access.requestNotifications() }
            }
            watchRow
                .modifier(RowEntrance(index: 3, shown: shown))
        }
        .frame(width: 370)
        .onChange(of: active, initial: true) { _, isActive in
            if isActive {
                shown = false
                withAnimation { shown = true }
                Task { await access.refresh() }
            }
        }
    }

    private func row(_ i: Int, icon: String, title: String, detail: String, state: DeviceAccess.State,
                     manage: (() -> Void)? = nil, request: @escaping () -> Void) -> some View {
        PermissionRow(icon: icon, title: title, detail: detail) {
            PermissionStatus(state: state, request: request, settings: access.openSettings, manage: manage)
        }
        .modifier(RowEntrance(index: i, shown: shown))
    }

    private var watchRow: some View {
        PermissionRow(icon: "applewatch", title: "Apple Watch", detail: watchDetail) {
            switch watch.status {
            case .paired(appInstalled: true):
                Sticker(text: "Paired", icon: "checkmark", fill: Twin.Palette.lime)
            case .paired(appInstalled: false):
                Sticker(text: "Open on watch", fill: Twin.Palette.paper)
            case .connecting:
                PixelSpinner(pixel: 4)
            case .notPaired, .unsupported:
                Sticker(text: "No watch", fill: Twin.Palette.paper)
            }
        }
    }

    private var watchDetail: String {
        switch watch.status {
        case .paired(appInstalled: true): "Counts scratching, even asleep"
        case .paired(appInstalled: false): "Install Eczema Twin from the Watch app"
        case .connecting: "Looking for your watch…"
        case .notPaired, .unsupported: "Pair one to count scratching. The demo works without it."
        }
    }
}

private struct RowEntrance: ViewModifier {
    let index: Int
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 22)
            .animation(Twin.Motion.spring.delay(0.1 + Double(index) * 0.08), value: shown)
    }
}

struct PermissionRow<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 40, height: 40)
                .sticker(Twin.Palette.cream)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Twin.Typeface.sans(15, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                Text(detail)
                    .font(Twin.Typeface.sans(12))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(12)
        .background(Twin.Palette.paper, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
        .accessibilityElement(children: .combine)
    }
}

/// "Allow" (pink, to do) → "On" (lime) or "Off" (opens Settings). Apple Health can also be
/// "Asked" (neutral): answered, but no data has come back yet, so it may well be off.
struct PermissionStatus: View {
    let state: DeviceAccess.State
    let request: () -> Void
    let settings: () -> Void
    /// Where "Asked" leads (Apple Health: the Health app).
    var manage: (() -> Void)? = nil

    var body: some View {
        Group {
            switch state {
            case .notAsked:
                Button("Allow", action: request)
                    .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink, height: 34, fullWidth: false))
                    .font(Twin.Typeface.sans(14, .bold))
            case .asked:
                Button(action: manage ?? settings) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Sticker(text: "Asked", fill: Twin.Palette.paper)
                        HStack(spacing: 3) {
                            Text("MANAGE IN HEALTH")
                            Image(systemName: "arrow.up.right").font(.system(size: 7, weight: .bold))
                        }
                        .font(Twin.Typeface.mono(9))
                        .foregroundStyle(Twin.Palette.inkMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Asked")
                .accessibilityHint("Opens Apple Health, where you choose what Eczema Twin can read")
                .transition(.opacity)
            case .on:
                Sticker(text: "On", icon: "checkmark", fill: Twin.Palette.lime)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            case .off:
                Button(action: settings) {
                    Sticker(text: "Off · Settings", fill: Twin.Palette.paper)
                }
                .buttonStyle(PressableStyle())
            case .unavailable:
                Text("Not on this device")
                    .font(Twin.Typeface.sans(12))
                    .foregroundStyle(Twin.Palette.inkHint)
            }
        }
        .animation(Twin.Motion.bouncy, value: state)
    }
}
