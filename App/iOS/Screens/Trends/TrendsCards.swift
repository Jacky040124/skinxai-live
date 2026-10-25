import SwiftUI
import EczemaKit

// MARK: - Detail strip of the selected night

/// Cyan strip under the timeline ("this item"): the selected night's minutes, sleep, humidity,
/// temperature and HRV (out-of-range values get an orange dot), and that day's events (tap one → its
/// sheet). The numbers roll when the selection moves.
struct TrendsNightDetail: View {
    let night: TrendsNight
    var onEvent: (TrendsEvent) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(night.eyebrow)
                        .font(Twin.Typeface.eyebrow)
                        .tracking(0.8)
                        .foregroundStyle(Twin.Palette.inkHint)
                        .lineLimit(1)
                        .contentTransition(.interpolate)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(night.minutes)")
                            .font(Twin.Typeface.sans(24, .bold))
                            .tracking(-0.5)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(night.minutes)))
                        Text(" min scratching")
                            .font(Twin.Typeface.sans(15))
                            .foregroundStyle(Twin.Palette.inkMuted)
                    }
                    .foregroundStyle(Twin.Palette.ink)
                }
                Spacer(minLength: 8)
                Group {
                    if night.hot {
                        Sticker(text: night.ratio, icon: "arrowtriangle.up.fill", fill: Twin.Palette.orange)
                    } else {
                        Sticker(text: "normal", fill: Twin.Palette.lime)
                    }
                }
                .id(night.hot ? night.ratio : "normal")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            HStack(spacing: 0) {
                ForEach(night.metrics) { metric in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label.uppercased())
                            .font(Twin.Typeface.mono(9, bold: true))
                            .tracking(0.4)
                            .foregroundStyle(Twin.Palette.inkHint)
                        HStack(spacing: 4) {
                            if metric.flagged {
                                Circle()
                                    .fill(Twin.Palette.orange)
                                    .overlay(Circle().strokeBorder(Twin.Palette.ink, lineWidth: 1))
                                    .frame(width: 7, height: 7)
                                    .transition(.scale.combined(with: .opacity))
                            }
                            Text(metric.value)
                                .font(Twin.Typeface.sans(15, .bold))
                                .foregroundStyle(Twin.Palette.ink)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .contentTransition(.numericText())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(metric.flagged ? "out of your usual range" : "")
                }
            }
            if !night.events.isEmpty {
                TrendsFlow(spacing: 6, lineSpacing: 6) {
                    ForEach(night.events) { event in
                        Button { onEvent(event) } label: {
                            HStack(spacing: 5) {
                                Text(event.emoji).font(.system(size: 11))
                                Text(eventText(event)).font(Twin.Typeface.sans(12, .bold)).lineLimit(1)
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(Twin.Palette.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .sticker(event.isProduct ? Twin.Palette.pink : Twin.Palette.paper)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint("Shows details")
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Twin.Palette.cyanSoft, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
    }

    /// "New body wash · night 4", "Wool sweater · night 1", "Exams", "Late gym".
    private func eventText(_ e: TrendsEvent) -> String {
        guard e.isProduct else { return e.shortName }
        return "\(e.shortName) · night \(night.id - e.start + 1)"
    }
}

// MARK: - Legend

/// "■ above usual  - - your usual · 12 min  ● out of range"
struct TrendsLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Twin.Palette.orange)
                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Twin.Palette.ink, lineWidth: 1))
                    .frame(width: 9, height: 9)
                Text("flare")
            }
            HStack(spacing: 5) {
                ChartHLine()
                    .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 16, height: 2)
                Text("usual \(StageStory.usual) min")
            }
            HStack(spacing: 5) {
                Circle()
                    .fill(Twin.Palette.orange)
                    .overlay(Circle().strokeBorder(Twin.Palette.ink, lineWidth: 1))
                    .frame(width: 7, height: 7)
                Text("out of range")
            }
            Spacer(minLength: 0)
        }
        .font(Twin.Typeface.mono(10))
        .foregroundStyle(Twin.Palette.inkHint)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - More charts

/// "More charts" disclosure row: tap to show the pattern cards under it.
struct TrendsMoreHeader: View {
    @Binding var open: Bool

    var body: some View {
        Button {
            withAnimation(Twin.Motion.spring) { open.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 34, height: 34)
                    .sticker(Twin.Palette.cream)
                VStack(alignment: .leading, spacing: 2) {
                    Text("More charts")
                        .font(Twin.Typeface.sans(16, .bold))
                        .foregroundStyle(Twin.Palette.ink)
                    Text("CALENDAR · TRIGGERS · SLEEP · WEEKDAYS")
                        .font(Twin.Typeface.mono(9, bold: true))
                        .tracking(0.3)
                        .foregroundStyle(Twin.Palette.inkHint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, Twin.Space.l)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Twin.Palette.paper, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
                .strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("More charts")
        .accessibilityValue(open ? "expanded" : "collapsed")
    }
}

// MARK: - Layout

/// Left-to-right wrapping layout for chips.
struct TrendsFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if x > 0, x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: width.isFinite ? width : widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
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
