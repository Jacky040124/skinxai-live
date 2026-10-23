import SwiftUI
import EczemaKit

/// Settings (avatar button): demo story or your own data, demo time travel, Claude model + key,
/// units, replay onboarding, about.
struct SettingsScreen: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataModeController
    @EnvironmentObject var tour: DemoTour
    @EnvironmentObject var toasts: ShellToasts
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profileName") private var name = "Douglas"

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Twin.Space.m) {
                header
                    .riseIn(0)
                profile
                    .riseIn(Twin.Motion.stagger)

                section("Data", index: 2) { DataSourceCard() }
                if app.dataset.isDemo {
                    section("Time travel", index: 3) {
                        StoryScrubberCard(playTour: playTour)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                section("Claude", index: 4) { ClaudeSettingsCard() }
                    .id("claude")
                section("Units", index: 5) { UnitsCard() }
                    .id("units")

                Button(action: replayOnboarding) {
                    Label("Replay onboarding", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(TwinButtonStyle(fill: Twin.Palette.paper, height: 50))
                .padding(.top, 4)
                .riseIn(6 * Twin.Motion.stagger)

                AboutCard()
                    .riseIn(7 * Twin.Motion.stagger)
                    .id("about")
            }
            .padding(.horizontal, Twin.Space.screen)
            .padding(.top, 22)
            .padding(.bottom, 40)
            .animation(Twin.Motion.spring, value: app.dataset.isDemo)
        }
        .onAppear {
            // `-scrollTo claude|units|about` (screenshots).
            if let target = UserDefaults.standard.string(forKey: "scrollTo") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo(target, anchor: .top) }
            }
        }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Twin.Palette.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Twin.Radius.dialog)
        .presentationBackground(Twin.Palette.paper)
        // Toasts raised while this sheet is up show here (the root's host is behind the sheet).
        .overlay(alignment: .top) { ShellToastHost() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .font(Twin.Typeface.largeTitle)
                    .tracking(-0.5)
                    .foregroundStyle(Twin.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(statusLine)
                    .font(Twin.Typeface.meta)
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.inkHint)
                    .contentTransition(.interpolate)
                    .animation(Twin.Motion.spring, value: statusLine)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 36, height: 36)
                    .sticker(Twin.Palette.paper)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close")
        }
    }

    private var statusLine: String {
        guard app.dataset.isDemo else { return "YOUR DATA · LIVE" }
        switch data.position {
        case .flare(let d): return "DEMO STORY · DAY \(d) OF \(StoryPoint.flareLength)"
        case .test(let d): return "DEMO STORY · TEST DAY \(d) OF \(StoryPoint.testLength)"
        }
    }

    private var profile: some View {
        HStack(spacing: 14) {
            Group {
                if let first = name.trimmingCharacters(in: .whitespaces).first {
                    Text(String(first).uppercased())
                        .font(Twin.Typeface.sans(20, .bold))
                        .contentTransition(.numericText())
                } else {
                    Image(systemName: "person.fill").font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundStyle(Twin.Palette.ink)
            .frame(width: 48, height: 48)
            .sticker(Twin.Palette.pink)
            .animation(Twin.Motion.bouncy, value: name.first)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Your name", text: $name)
                    .font(Twin.Typeface.sans(18, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                Text("On your avatar and your doctor report")
                    .font(Twin.Typeface.sans(13))
                    .foregroundStyle(Twin.Palette.inkMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Twin.Palette.inkHint)
        }
        .twinCard()
    }

    private func section<Content: View>(_ title: String, index: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title)
                .padding(.leading, 2)
                .padding(.top, 8)
            content()
        }
        .riseIn(Double(index) * Twin.Motion.stagger)
    }

    private func playTour() {
        dismiss()
        tour.start(app: app, delay: 0.6)
    }

    private func replayOnboarding() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { app.showOnboarding = true }
    }
}

// MARK: - Data source

private struct DataSourceCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataModeController
    @EnvironmentObject var access: DeviceAccess
    @EnvironmentObject var watch: WatchInbox
    @EnvironmentObject var toasts: ShellToasts

    var body: some View {
        let demo = data.mode == .demo
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(get: { data.mode == .demo }, set: { on in
                withAnimation(Twin.Motion.spring) { data.setMode(on ? .demo : .real) }
                toasts.show(on ? "Demo story on · Douglas's 14 days" : "Your data · watch, Health and weather", mood: .info)
            })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Demo story")
                        .font(Twin.Typeface.sans(16, .bold))
                        .foregroundStyle(Twin.Palette.ink)
                    Text(demo ? "Douglas's 14 days, the same on every launch. Turn off to use your own watch, Health and local weather."
                              : "Your own data: scratching from your watch, sleep and stress from Health, weather where you are.")
                        .font(Twin.Typeface.sans(13))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(SettingsSwitchStyle())

            if !demo {
                VStack(spacing: 0) {
                    statusRow("applewatch", "Apple Watch") { watchStatus }
                    statusRow("heart.fill", "Apple Health") {
                        PermissionStatus(state: access.health, request: { Task { await access.requestHealth(); await data.refreshReal(force: true) } },
                                         settings: access.openSettings)
                    }
                    statusRow("location.fill", "Location") {
                        PermissionStatus(state: access.location, request: access.requestLocation, settings: access.openSettings)
                    }
                    statusRow("cloud.sun.fill", "Weather", last: true) { weather }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .twinCard()
        .onChange(of: access.location) { _, state in
            if state == .on { Task { await data.refreshReal(force: true) } }
        }
    }

    private func statusRow<Trailing: View>(_ icon: String, _ title: String, last: Bool = false,
                                           @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 32, height: 32)
                .sticker(Twin.Palette.cream)
            Text(title)
                .font(Twin.Typeface.sans(15, .semibold))
                .foregroundStyle(Twin.Palette.ink)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Twin.Palette.hairline).frame(height: 1) }
    }

    @ViewBuilder private var watchStatus: some View {
        switch watch.status {
        case .paired(appInstalled: true):
            VStack(alignment: .trailing, spacing: 2) {
                Sticker(text: "Paired", icon: "checkmark", fill: Twin.Palette.lime)
                if let last = watch.lastSync {
                    Text("SYNCED \(last.formatted(date: .omitted, time: .shortened).uppercased())")
                        .font(Twin.Typeface.mono(9))
                        .foregroundStyle(Twin.Palette.inkHint)
                }
            }
        case .paired(appInstalled: false): Sticker(text: "Open the watch app", fill: Twin.Palette.paper)
        case .connecting: PixelSpinner(pixel: 4)
        case .notPaired, .unsupported: Sticker(text: "No watch", fill: Twin.Palette.paper)
        }
    }

    private var weather: some View {
        HStack(spacing: 8) {
            if let now = data.environment?.current {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(weatherLine(now))
                        .font(Twin.Typeface.sans(13, .semibold))
                        .foregroundStyle(Twin.Palette.ink)
                    Text("UPDATED \(now.time.formatted(date: .omitted, time: .shortened).uppercased())")
                        .font(Twin.Typeface.mono(9))
                        .foregroundStyle(Twin.Palette.inkHint)
                }
            } else {
                Text(access.location == .on ? "Not loaded yet" : "Needs location")
                    .font(Twin.Typeface.sans(13))
                    .foregroundStyle(Twin.Palette.inkHint)
            }
            Button {
                Task { await data.refreshReal(force: true) }
            } label: {
                Group {
                    if data.refreshing { PixelSpinner(pixel: 3) } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 30, height: 30)
                .sticker(Twin.Palette.paper)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Refresh weather and Health")
        }
    }

    private func weatherLine(_ r: EnvironmentReading) -> String {
        var parts: [String] = []
        if let t = r.tempC { parts.append(TwinUnits.temperature(t)) }
        if let h = r.humidityPct { parts.append("\(Int(h))%") }
        if let a = r.aqi { parts.append("AQI \(a)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Raft switch

/// Switches may be round (Raft). On = yellow track ("selected"), ink edges, springy knob.
private struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 14) {
            configuration.label
            Spacer(minLength: 0)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Twin.Palette.yellow : Twin.Palette.fill)
                    .overlay(Capsule().strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                Circle()
                    .fill(Twin.Palette.paper)
                    .overlay(Circle().strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                    .padding(4)
            }
            .frame(width: 54, height: 32)
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            configuration.isOn.toggle()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

// MARK: - Units

private struct UnitsCard: View {
    @AppStorage(TwinUnits.temperatureKey) private var unit = "c"
    @Namespace private var ns

    var body: some View {
        HStack {
            Text("Temperature")
                .font(Twin.Typeface.sans(16, .bold))
                .foregroundStyle(Twin.Palette.ink)
            Spacer()
            HStack(spacing: 0) {
                ForEach([("c", "°C"), ("f", "°F")], id: \.0) { value, label in
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) { unit = value }
                    } label: {
                        Text(label)
                            .font(Twin.Typeface.mono(14, bold: true))
                            .foregroundStyle(Twin.Palette.ink)
                            .frame(width: 56, height: 34)
                            .background {
                                if unit == value {
                                    RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                                        .fill(Twin.Palette.yellow)
                                        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                                            .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                                        .matchedGeometryEffect(id: "unit", in: ns)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(unit == value ? [.isSelected] : [])
                }
            }
            .padding(3)
            .background(Twin.Palette.fill, in: RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous).strokeBorder(Twin.Palette.hairline, lineWidth: 1))
        }
        .twinCard()
    }
}

// MARK: - About

private struct AboutCard: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Eczema Twin")
                    .font(Twin.Typeface.sans(17, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                Spacer()
                Text("VERSION \(version)")
                    .font(Twin.Typeface.meta)
                    .foregroundStyle(Twin.Palette.inkHint)
            }
            Text("Your Apple Watch knows when you scratch. Claude tells you why.")
                .font(Twin.Typeface.sans(15))
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                credit("Built at CalHacks 13.0")
                credit("Scratch detection from wrist motion, after Lilly et al. (2023)")
                credit("Weather and air quality: Open-Meteo")
                credit("Type: Space Grotesk and Space Mono (SIL Open Font License)")
            }
            Text("Not a medical device and not a diagnosis. If skin oozes, crusts or you get a fever, see a doctor today.")
                .font(Twin.Typeface.sans(12))
                .foregroundStyle(Twin.Palette.inkMuted)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(Twin.Palette.red).frame(width: 2) }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .twinCard(fill: Twin.Palette.cream)
    }

    private func credit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Rectangle().fill(Twin.Palette.inkFaint).frame(width: 5, height: 5).offset(y: -2)
            Text(text)
                .font(Twin.Typeface.sans(13))
                .foregroundStyle(Twin.Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
