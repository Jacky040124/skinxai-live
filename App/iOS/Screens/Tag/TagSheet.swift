import SwiftUI
import EczemaKit

// MARK: - Host (scrim + sliding panel)

/// Presents `TagSheet` as a Raft bottom sheet: paper panel with a 1.5 pt ink top edge and
/// 16 pt top corners over a 40% scrim. Slides up with a spring, follows the finger when dragged
/// down, closes on a fast or long drag, a scrim tap, or the VoiceOver escape gesture.
struct TagSheetHost: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0

    static func openAnimation(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.44, dampingFraction: 0.86)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if app.showTagSheet {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { close() }
                        .accessibilityLabel("Close")
                        .accessibilityAddTraits(.isButton)

                    TagSheet(close: close, bottomInset: proxy.safeAreaInsets.bottom)
                        .offset(y: offset)
                        .gesture(dragToDismiss)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { close() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(Self.openAnimation(reduceMotion), value: app.showTagSheet)
    }

    /// Down: 1:1 with the finger. Up: rubber band.
    private var offset: CGFloat { drag > 0 ? drag : -sqrt(-drag) * 2.2 }

    private var dragToDismiss: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag = $0.translation.height }
            .onEnded { value in
                let fast = value.predictedEndTranslation.height - value.translation.height > 220
                if value.translation.height > 130 || (fast && value.translation.height > 20) {
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { drag = 0 }
                } else {
                    withAnimation(Twin.Motion.bouncy) { drag = 0 }
                }
            }
    }

    private func close() {
        withAnimation(Self.openAnimation(reduceMotion)) { app.showTagSheet = false }
    }
}

// MARK: - Sheet

/// "Anything new today?" — one tap per thing, everything else is tracked automatically.
struct TagSheet: View {
    var close: () -> Void
    /// Home-indicator inset: the panel reaches the screen bottom, its content stays above it.
    var bottomInset: CGFloat = 0
    @EnvironmentObject var app: AppState
    @EnvironmentObject var toasts: ToastCenter
    @EnvironmentObject var data: DataModeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selected: [ExposureKind] = []
    @State private var scan: LabelScanResult?
    @State private var scanning = false
    @State private var shown = false

    private var todayRecord: DayRecord? { app.dataset.today }
    /// Kinds the user already tagged today (shown with a small check).
    private var logged: Set<ExposureKind> {
        Set(todayRecord?.exposures.filter { !$0.automatic }.map(\.kind) ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Twin.Palette.hairline)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                Text("Anything new today?")
                    .font(Twin.Typeface.sans(22, .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Twin.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("ONE TAP")
                    .font(Twin.Typeface.meta)
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.inkHint)
                    .accessibilityHidden(true)
            }
            Text("Everything else is tracked for you.")
                .font(Twin.Typeface.sans(14))
                .foregroundStyle(Twin.Palette.inkMuted)
                .padding(.top, 4)

            ChipFlow(spacing: 10, lineSpacing: 10) {
                ForEach(Array(ExposureKind.taggable.enumerated()), id: \.element) { i, kind in
                    TagChip(kind: kind, selected: selected.contains(kind), logged: logged.contains(kind)) {
                        toggle(kind)
                    }
                    // Only the entrance (fade + rise) is animated, never the chip's layout position.
                    .animation(Twin.Motion.spring.delay(0.1 + Double(i) * 0.025)) { chip in
                        chip.opacity(shown ? 1 : 0).offset(y: shown || reduceMotion ? 0 : 12)
                    }
                }
            }
            .padding(.top, 18)

            if let scan {
                ScanResultCard(result: scan) {
                    withAnimation(Twin.Motion.spring) { self.scan = nil }
                }
                .padding(.top, 16)
                .transition(.asymmetric(insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                                        removal: .opacity))
            }

            Button { scanning = true } label: {
                Label {
                    Text(scan == nil ? "Scan a product label" : "Scan another label")
                } icon: {
                    Image(systemName: "text.viewfinder").font(.system(size: 17, weight: .semibold))
                }
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.paper, height: 50))
            .padding(.top, 18)

            Button(action: save) {
                HStack(spacing: 8) {
                    Text("Save")
                    if !newKinds.isEmpty {
                        Text("\(newKinds.count)")
                            .font(Twin.Typeface.mono(12, bold: true))
                            .contentTransition(.numericText())
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Twin.Palette.paper, in: RoundedRectangle(cornerRadius: Twin.Radius.sticker))
                            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.sticker).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .animation(Twin.Motion.bouncy, value: newKinds.count)
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.yellow, height: 52))
            .padding(.top, 10)
            .accessibilityLabel(newKinds.isEmpty ? "Save" : "Save \(newKinds.count) new")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14 + bottomInset)
        .background(alignment: .top) {
            // Panel: extends below the screen so only the top edge and corners show the ink line.
            UnevenRoundedRectangle(topLeadingRadius: Twin.Radius.dialog, topTrailingRadius: Twin.Radius.dialog, style: .continuous)
                .fill(Twin.Palette.paper)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: Twin.Radius.dialog, topTrailingRadius: Twin.Radius.dialog, style: .continuous)
                        .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink)
                )
                .padding(.bottom, -400)
        }
        .contentShape(Rectangle())
        .onAppear { DispatchQueue.main.async { shown = true } }
        .onReceive(NotificationCenter.default.publisher(for: .shellDemo)) { note in
            guard let command = note.object as? String else { return }
            if command == "tag.save" { save() }
            if command == "tag.scan" { scanning = true }
            if command.hasPrefix("tag.toggle:"), let kind = ExposureKind(rawValue: String(command.dropFirst("tag.toggle:".count))) {
                toggle(kind)
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            LabelScanView { result in
                withAnimation(Twin.Motion.spring) {
                    scan = result
                    if !selected.contains(.newProduct) { selected.append(.newProduct) }
                }
                Haptics.success()
            }
        }
    }

    /// Selected kinds that are not in today's log yet (a scanned label is always a new product).
    private var newKinds: [ExposureKind] {
        selected.filter { !logged.contains($0) || ($0 == .newProduct && scan != nil) }
    }

    private func toggle(_ kind: ExposureKind) {
        Haptics.tap()
        withAnimation(Twin.Motion.bouncy) {
            if let i = selected.firstIndex(of: kind) { selected.remove(at: i) } else { selected.append(kind) }
        }
    }

    private func save() {
        let kinds = ExposureKind.taggable.filter { newKinds.contains($0) }
        guard !kinds.isEmpty else {
            if !selected.isEmpty { toasts.show("Already in today's log", mood: .info) }
            close()
            return
        }
        let scanned = scan
        var added: [Exposure] = []
        app.update { d in
            guard let i = d.days.indices.last else { return }
            for kind in kinds {
                var title = kind.label
                var note: String?
                if kind == .newProduct, let scanned {
                    title = scanned.title
                    note = scanned.note
                }
                let exposure = Exposure(kind: kind, title: title, day: d.days[i].day, automatic: false, note: note)
                d.days[i].exposures.append(exposure)
                added.append(exposure)
            }
        }
        data.didTag(added)
        Haptics.success()
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            toasts.show("Saved · Claude will include it")
        }
    }
}

// MARK: - Chip

private struct TagChip: View {
    let kind: ExposureKind
    let selected: Bool
    let logged: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pops = 0

    var body: some View {
        Button {
            action()
            pops += 1
        } label: {
            HStack(spacing: 7) {
                Text(kind.emoji)
                    .font(.system(size: 16))
                    .keyframeAnimator(initialValue: 0.0, trigger: pops) { view, angle in
                        view.rotationEffect(.degrees(reduceMotion ? 0 : angle))
                    } keyframes: { _ in
                        CubicKeyframe(-14, duration: 0.08)
                        CubicKeyframe(10, duration: 0.1)
                        CubicKeyframe(-5, duration: 0.1)
                        SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                    }
                Text(kind.label)
                    .font(Twin.Typeface.sans(15, .semibold))
                    .foregroundStyle(Twin.Palette.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? Twin.Palette.yellow : Twin.Palette.paper,
                        in: RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
                .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
            .overlay(alignment: .topTrailing) {
                if logged {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(Twin.Palette.ink)
                        .frame(width: 16, height: 16)
                        .sticker(Twin.Palette.lime)
                        .offset(x: 6, y: -6)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(ChipPressStyle())
        .keyframeAnimator(initialValue: 1.0, trigger: pops) { view, scale in
            view.scaleEffect(reduceMotion ? 1 : scale)
        } keyframes: { _ in
            CubicKeyframe(1.12, duration: 0.12)
            SpringKeyframe(1.0, duration: 0.45, spring: .init(response: 0.35, dampingRatio: 0.5))
        }
        .accessibilityLabel(kind.label)
        .accessibilityValue(logged ? "logged today" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct ChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Flow layout

/// Left-aligned wrapping rows (chips).
private struct ChipFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
