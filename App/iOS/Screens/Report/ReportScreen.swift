import SwiftUI
import QuickLook
import EczemaKit

/// "Share with my doctor": the one-page report, printed out in the app, exported as a PDF.
struct ReportScreen: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var toasts: ShellToasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("profileName") private var name = "Douglas"

    @State private var pdf: URL?
    @State private var preview: Image?
    @State private var printed = false
    @State private var fullScreen: URL?

    private var facts: ReportFacts { ReportFacts(dataset: app.dataset, name: name) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Twin.Space.m) {
                header
                    .riseIn(0)
                paper
                    .riseIn(0.05, distance: 0)
                included
                    .riseIn(0.25)
                actions
                    .riseIn(0.32)
                Text("Nothing leaves your phone until you share it. The PDF has no account, no tracking, just this page.")
                    .font(Twin.Typeface.sans(12))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .fixedSize(horizontal: false, vertical: true)
                    .riseIn(0.38)
            }
            .padding(.horizontal, Twin.Space.screen)
            .padding(.top, 22)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .background(Twin.Palette.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Twin.Radius.dialog)
        .presentationBackground(Twin.Palette.paper)
        .quickLookPreview($fullScreen)
        .task { await printOut() }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Share with my doctor")
                    .font(Twin.Typeface.largeTitle)
                    .tracking(-0.5)
                    .foregroundStyle(Twin.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("ONE PAGE · PDF · \(rangeText)")
                    .font(Twin.Typeface.meta)
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.inkHint)
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

    private var rangeText: String {
        let f = facts
        let a = f.windowStart.formatted(.dateTime.month(.abbreviated).day())
        let b = f.windowEnd.formatted(.dateTime.month(.abbreviated).day())
        return "\(a) – \(b)".uppercased()
    }

    /// The page comes out of a "printer slot" at the top of the tray, then its sections fill in.
    private var paper: some View {
        PaperTray { GeometryReader { g in
            let inner = g.size.width - 28
            let scale = inner / ReportPage.size.width
            let pageH = ReportPage.size.height * scale
            ZStack(alignment: .top) {
                ReportPage(facts: facts, animated: !reduceMotion)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: inner, height: pageH, alignment: .topLeading)
                    .overlay(Rectangle().strokeBorder(Twin.Palette.hairline, lineWidth: 1))
                    .offset(y: printed || reduceMotion ? 0 : -pageH - 6)
                    .padding(.top, 14)
                    .frame(width: g.size.width, height: pageH + 28, alignment: .top)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { if pdf != nil { fullScreen = pdf } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Report preview")
                    .accessibilityHint("Opens the PDF full screen")
                    .accessibilityAddTraits(.isButton)
                // The slot.
                Capsule()
                    .fill(Twin.Palette.ink)
                    .frame(width: g.size.width - 28, height: 4)
                    .padding(.top, 10)
            }
            .background(Twin.Palette.cream, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous).strokeBorder(Twin.Palette.hairline, lineWidth: 1))
        } }
    }

    private var included: some View {
        let f = facts
        var items: [(String, String)] = [("chart.bar.fill", "\(f.dayCount)-day chart")]
        if f.caseFile != nil { items.append(("sparkle", "Top suspects")) }
        if f.experiment != nil { items.append(("flask", "Test result")) }
        if !f.vitals.isEmpty { items.append(("moon.zzz.fill", "Sleep & stress")) }
        items.append(("exclamationmark.shield", "Disclaimer"))
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "On the page")
            ReportChipRow(items: items)
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if let pdf {
                ShareLink(item: pdf, preview: SharePreview("Eczema Twin report · \(name)", image: preview ?? Image(systemName: "doc.richtext"))) {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink, height: 52))
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                .transition(.opacity)
            } else {
                HStack(spacing: 10) {
                    PixelSpinner()
                    Text("Preparing the PDF…")
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .font(Twin.Typeface.sans(16, .bold))
                .foregroundStyle(Twin.Palette.inkMuted)
                .background(Twin.Palette.fill, in: RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous))
                .transition(.opacity)
            }
            Button {
                fullScreen = pdf
            } label: {
                Label("Open full screen", systemImage: "doc.viewfinder")
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.paper, height: 48))
            .disabled(pdf == nil)
            .opacity(pdf == nil ? 0.5 : 1)
        }
        .animation(Twin.Motion.spring, value: pdf != nil)
    }

    // MARK: Printing

    private func printOut() async {
        try? await Task.sleep(nanoseconds: 250_000_000)
        if !reduceMotion {
            // Feed ticks while the page comes out.
            withAnimation(.timingCurve(0.25, 0.8, 0.3, 1, duration: 1.15)) { printed = true }
            for _ in 0..<5 {
                Haptics.soft()
                try? await Task.sleep(nanoseconds: 170_000_000)
            }
            try? await Task.sleep(nanoseconds: 450_000_000)
        } else {
            printed = true
        }
        let rendered = ReportPDF.render(facts)
        withAnimation(Twin.Motion.bouncy) {
            pdf = rendered.url
            preview = rendered.thumbnail.map { Image(uiImage: $0) }
        }
        if rendered.url == nil { toasts.show("Couldn't make the PDF", mood: .warning) }
    }
}

/// Sizes the paper tray from its width: the page (Letter ratio) plus the tray margins.
private struct PaperTray: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 398
        return CGSize(width: w, height: (w - 28) * ReportPage.size.height / ReportPage.size.width + 28)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for v in subviews { v.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}

/// Small stickers listing what the page contains.
private struct ReportChipRow: View {
    let items: [(String, String)]
    var body: some View {
        ChipWrap(spacing: 6) {
            ForEach(items, id: \.1) { icon, text in
                HStack(spacing: 5) {
                    Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                    Text(text).font(Twin.Typeface.sans(12, .semibold))
                }
                .foregroundStyle(Twin.Palette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .sticker(Twin.Palette.paper)
            }
        }
    }
}

private struct ChipWrap: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth { y += line + spacing; x = 0; line = 0 }
            x += s.width + spacing
            line = max(line, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += line + spacing; x = bounds.minX; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}

/// Draws `ReportPage` into a one-page PDF (vector text, embedded fonts) and a thumbnail.
@MainActor
enum ReportPDF {
    static func render(_ facts: ReportFacts) -> (url: URL?, thumbnail: UIImage?) {
        let page = ReportPage(facts: facts, animated: false)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(ReportPage.size)

        let day = facts.generated.formatted(.iso8601.year().month().day())
        let safeName = facts.name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined()
            .trimmingCharacters(in: .whitespaces)
        let who = safeName.isEmpty ? "" : " - \(safeName.prefix(40))"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Eczema Twin report\(who) - \(day).pdf")
        try? FileManager.default.removeItem(at: url)

        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: ReportPage.size)
            let info: [CFString: Any] = [
                kCGPDFContextTitle: "Eczema Twin report",
                kCGPDFContextCreator: "Eczema Twin",
                kCGPDFContextAuthor: facts.name,
            ]
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }

        let thumb = ImageRenderer(content: page)
        thumb.proposedSize = ProposedViewSize(ReportPage.size)
        thumb.scale = 0.5
        return (ok ? url : nil, thumb.uiImage)
    }
}
