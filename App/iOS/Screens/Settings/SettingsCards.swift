import SwiftUI
import EczemaKit

// MARK: - Time travel

/// The whole demo story as a strip of bars (14 flare-story days, then the 10-day test).
/// Tap or slide across it to make that day "today"; a yellow sticker marks where you are.
struct TimeTravelCard: View {
    var playTour: () -> Void
    @EnvironmentObject var data: DataModeController
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns
    @State private var preview: StoryPoint?
    @State private var grown = false

    private let points = StoryPoint.all
    private var maxMinutes: Double { max(1, points.map(\.minutes).max() ?? 1) }

    var body: some View {
        let current = preview ?? data.position
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.title(current))
                        .font(Twin.Typeface.sans(17, .bold))
                        .foregroundStyle(Twin.Palette.ink)
                        .contentTransition(.interpolate)
                    Text(Self.detail(current))
                        .font(Twin.Typeface.sans(13))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .contentTransition(.interpolate)
                }
                .animation(Twin.Motion.spring, value: current)
                Spacer(minLength: 0)
                // The day shown as "today" counts only the hours so far (like the Today screen).
                let isToday = current == data.position
                VStack(alignment: .trailing, spacing: 0) {
                    CountUp(value: isToday ? (app.dataset.today?.scratchMinutes ?? current.minutes) : current.minutes,
                            font: Twin.Typeface.sans(28, .bold), duration: 0.45)
                        .tracking(-1)
                    Text(isToday ? "MIN SO FAR" : "MIN THAT DAY")
                        .font(Twin.Typeface.mono(9))
                        .foregroundStyle(Twin.Palette.inkHint)
                }
            }

            chart(current)
                .frame(height: 104)
                .accessibilityElement()
                .accessibilityLabel("Story timeline")
                .accessibilityValue(Self.title(current))
                .accessibilityAdjustableAction { direction in
                    let i = current.index + (direction == .increment ? 1 : -1)
                    if points.indices.contains(i) { commit(points[i]) }
                }

            HStack(spacing: 10) {
                if data.position != .flare(StoryPoint.flareLength) {
                    Button { commit(.flare(StoryPoint.flareLength)) } label: {
                        Label("Day \(StoryPoint.flareLength)", systemImage: "arrow.uturn.backward")
                            .lineLimit(1)
                    }
                    .buttonStyle(TwinButtonStyle(fill: Twin.Palette.paper, height: 42, fullWidth: false))
                    .accessibilityLabel("Back to day \(StoryPoint.flareLength)")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Button(action: playTour) {
                    Label("Play the demo tour", systemImage: "play.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink, height: 42))
            }
            .font(Twin.Typeface.sans(14, .bold))
            .animation(Twin.Motion.spring, value: data.position)
        }
        .twinCard()
        .sensoryFeedback(.selection, trigger: preview)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.6, dampingFraction: 0.75).delay(0.25)) { grown = true }
        }
    }

    // MARK: Chart

    private func chart(_ current: StoryPoint) -> some View {
        GeometryReader { geo in
            let n = points.count
            let gap: CGFloat = 3, groupGap: CGFloat = 12
            let barW = (geo.size.width - gap * CGFloat(n - 2) - groupGap) / CGFloat(n)
            let barArea: CGFloat = 70
            let x: (Int) -> CGFloat = { i in CGFloat(i) * (barW + gap) + (i >= StoryPoint.flareLength ? groupGap - gap : 0) }
            let index: (CGFloat) -> Int = { px in
                var best = 0
                for i in 0..<n where abs(x(i) + barW / 2 - px) < abs(x(best) + barW / 2 - px) { best = i }
                return best
            }

            ZStack(alignment: .topLeading) {
                // The test period.
                let testStart = x(StoryPoint.flareLength) - 5
                let testEnd = x(n - 1) + barW + 5
                RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                    .fill(Twin.Palette.cyanSoft)
                    .frame(width: testEnd - testStart, height: barArea + 6)
                    .offset(x: testStart, y: -2)
                Text("10-DAY TEST")
                    .font(Twin.Typeface.mono(8, bold: true))
                    .tracking(0.5)
                    .foregroundStyle(Twin.Palette.cyanStrong)
                    .offset(x: testStart + 6, y: 3)

                ForEach(points, id: \.self) { p in
                    let i = p.index
                    let h = max(4, p.minutes / maxMinutes * (barArea - 16))
                    let flare = p.minutes > 20
                    let on = p == current
                    ZStack(alignment: .bottom) {
                        if on {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Twin.Palette.yellow)
                                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                                .frame(width: barW + 7, height: h + 8)
                                .offset(y: 4)
                                .matchedGeometryEffect(id: "here", in: ns)
                        }
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(flare ? Twin.Palette.orange : Twin.Palette.ink.opacity(on ? 0.45 : 0.16))
                            .overlay {
                                if flare {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: 1)
                                }
                            }
                            .frame(width: barW, height: grown ? h : 3)
                            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7).delay(Double(i) * 0.02), value: grown)
                    }
                    .frame(width: barW + 7, height: barArea, alignment: .bottom)
                    .offset(x: x(i) - 3.5, y: 0)
                }

                // Axis labels.
                label("DAY 1", at: x(0), width: 60, alignment: .leading, y: barArea + 12)
                label("DAY \(StoryPoint.flareLength)", at: x(StoryPoint.flareLength - 1) + barW + 2 - 60, width: 60, alignment: .trailing, y: barArea + 12)
                label("TEST DAY \(StoryPoint.testLength)", at: x(n - 1) + barW - 90, width: 90, alignment: .trailing, y: barArea + 12)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.74), value: current)
            .contentShape(Rectangle())
            .onTapGesture(count: 1, coordinateSpace: .local) { location in
                commit(points[index(location.x)])
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .onChanged { v in
                        guard abs(v.translation.width) > abs(v.translation.height) || preview != nil else { return }
                        let p = points[index(v.location.x)]
                        if p != preview { preview = p }
                    }
                    .onEnded { _ in
                        if let p = preview { commit(p) }
                    }
            )
        }
    }

    private func label(_ text: String, at x: CGFloat, width: CGFloat, alignment: Alignment, y: CGFloat) -> some View {
        Text(text)
            .font(Twin.Typeface.mono(9))
            .foregroundStyle(Twin.Palette.inkHint)
            .frame(width: width, alignment: alignment)
            .offset(x: x, y: y)
    }

    private func commit(_ p: StoryPoint) {
        preview = nil
        guard p != data.position else { return }
        Haptics.success()
        data.travel(to: p)
    }

    // MARK: Copy (from the story's own markers)

    static func title(_ p: StoryPoint) -> String {
        switch p {
        case .flare(let d):
            let i = d - 1
            if d == StoryPoint.flareLength { return "Day \(d) · today" }
            if i == DemoData.bodyWashDay { return "Day \(d) · new body wash" }
            if i == DemoData.dryAirDay { return "Day \(d) · the air turns dry" }
            if i == DemoData.flareStartDay { return "Day \(d) · the flare starts" }
            if DemoData.examDays.contains(i) { return "Day \(d) · exam week" }
            return i < DemoData.flareStartDay ? "Day \(d) · a calm day" : "Day \(d) · still flaring"
        case .test(let d):
            if d == 1 { return "Test day 1 · wash paused" }
            if d == StoryPoint.testLength { return "Test day \(d) · the result" }
            return "Test day \(d) of \(StoryPoint.testLength)"
        }
    }

    static func detail(_ p: StoryPoint) -> String {
        switch p {
        case .flare(let d):
            return d == StoryPoint.flareLength ? "Claude's case file is ready." : "Claude is still collecting days."
        case .test(let d):
            let left = StoryPoint.testLength - d
            return left == 0 ? "Ten days without the body wash." : "\(left) more \(left == 1 ? "day" : "days") without the body wash."
        }
    }
}

// MARK: - Claude

/// Model (OpenRouter slug, UserDefaults "aiModel") and API key (Keychain). See `SettingsAI`.
struct ClaudeCard: View {
    @AppStorage(SettingsAI.modelKey) private var model = SettingsAI.defaultModel
    @EnvironmentObject var toasts: ToastCenter
    @Namespace private var ns
    @State private var otherSelected = false
    @State private var draft = ""
    @State private var hasKey = SettingsKeychain.hasKey
    @FocusState private var focus: Field?

    private enum Field { case slug, key }

    private var presetSelected: Bool { SettingsAI.presets.contains { $0.slug == model } && !otherSelected }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Model")
                    .font(Twin.Typeface.sans(16, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                Spacer()
                Text("VIA OPENROUTER")
                    .font(Twin.Typeface.mono(10))
                    .foregroundStyle(Twin.Palette.inkHint)
            }

            VStack(spacing: 2) {
                ForEach(SettingsAI.presets, id: \.slug) { preset in
                    modelRow(name: preset.name, note: preset.note, on: presetSelected && model == preset.slug) {
                        otherSelected = false
                        model = preset.slug
                        focus = nil
                    }
                }
                modelRow(name: "Other model", note: "Any OpenRouter slug", on: !presetSelected) {
                    otherSelected = true
                    focus = .slug
                }
            }
            .padding(3)
            .background(Twin.Palette.fill, in: RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous))

            if !presetSelected {
                TextField("provider/model", text: $model)
                    .font(Twin.Typeface.mono(14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focus, equals: .slug)
                    .submitLabel(.done)
                    .modifier(FieldChrome(focused: focus == .slug))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle().fill(Twin.Palette.hairline).frame(height: 1)

            HStack(alignment: .center) {
                Text("API key")
                    .font(Twin.Typeface.sans(16, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                Spacer()
                if hasKey {
                    Sticker(text: "In Keychain", icon: "checkmark", fill: Twin.Palette.lime)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    Sticker(text: "Not set", fill: Twin.Palette.paper)
                        .transition(.opacity)
                }
            }

            if hasKey {
                HStack {
                    Text("•••• •••• •••• ••••")
                        .font(Twin.Typeface.mono(15, bold: true))
                        .foregroundStyle(Twin.Palette.ink)
                        .accessibilityLabel("Key hidden")
                    Spacer()
                    Button("Remove", action: remove)
                        .buttonStyle(TwinButtonStyle(fill: Twin.Palette.paper, height: 38, fullWidth: false))
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 8) {
                    SecureField("Paste your OpenRouter key", text: $draft)
                        .font(Twin.Typeface.mono(14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .focused($focus, equals: .key)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .modifier(FieldChrome(focused: focus == .key))
                    Button("Save", action: save)
                        .buttonStyle(TwinButtonStyle(fill: Twin.Palette.yellow, height: 46, fullWidth: false))
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                }
                .transition(.opacity)
            }

            Text("Without a key, Insight shows the bundled analysis. The key stays in the iOS Keychain on this iPhone and is only sent to OpenRouter.")
                .font(Twin.Typeface.sans(12))
                .foregroundStyle(Twin.Palette.inkHint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .twinCard()
        .animation(Twin.Motion.spring, value: hasKey)
        .animation(Twin.Motion.spring, value: presetSelected)
        .onAppear { otherSelected = !SettingsAI.presets.contains { $0.slug == model } }
    }

    private func modelRow(name: String, note: String, on: Bool, select: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.75)) { select() }
        } label: {
            HStack(spacing: 10) {
                Text(name)
                    .font(Twin.Typeface.sans(15, on ? .bold : .medium))
                    .foregroundStyle(Twin.Palette.ink)
                Text(note)
                    .font(Twin.Typeface.sans(12))
                    .foregroundStyle(on ? Twin.Palette.ink.opacity(0.7) : Twin.Palette.inkHint)
                Spacer(minLength: 4)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Twin.Palette.ink)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                        .fill(Twin.Palette.yellow)
                        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                        .matchedGeometryEffect(id: "model", in: ns)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func save() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if SettingsKeychain.save(draft) {
            draft = ""
            focus = nil
            hasKey = true
            Haptics.success()
            toasts.show("Key saved in the Keychain")
        } else {
            Haptics.warning()
            toasts.show("The Keychain didn't accept the key", mood: .warning)
        }
    }

    private func remove() {
        SettingsKeychain.delete()
        hasKey = false
        toasts.show("Key removed · bundled analysis", mood: .info)
    }
}

/// Raft input: 1.5 pt ink edge, control radius; a yellow focus ring.
private struct FieldChrome: ViewModifier {
    var focused: Bool
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Twin.Palette.ink)
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Twin.Palette.paper, in: RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
                .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
            .background(RoundedRectangle(cornerRadius: Twin.Radius.control + 3, style: .continuous)
                .fill(Twin.Palette.yellow)
                .padding(-3)
                .opacity(focused ? 1 : 0))
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
