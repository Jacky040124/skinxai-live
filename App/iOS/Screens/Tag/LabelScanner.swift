import SwiftUI
import AVFoundation
import PhotosUI
import Vision
import VisionKit
import EczemaKit

// MARK: - Result

/// What the label check found. Everything runs on the phone (VisionKit / Vision OCR).
struct LabelScanResult: Equatable {
    struct Finding: Equatable, Identifiable {
        var id: String { name }
        let name: String        // "Fragrance"
        let matched: [String]   // terms seen on the label, e.g. ["parfum", "linalool"]
    }
    let findings: [Finding]
    let wordCount: Int

    /// Exposure title for today's log.
    var title: String {
        guard !findings.isEmpty else { return "New product · label checked" }
        let names = findings.prefix(2).map { $0.name.lowercased() }
        return "New product · " + names.joined(separator: ", ")
    }
    /// Exposure note Claude gets with the log.
    var note: String {
        guard !findings.isEmpty else { return "Label scanned: no common irritants found." }
        return "Label scanned. Contains: " + findings.map { "\($0.name) (\($0.matched.joined(separator: ", ")))" }.joined(separator: "; ") + "."
    }
}

/// Common contact irritants / allergens in skin-care labels (informational, not a diagnosis).
enum IrritantCheck {
    private static let groups: [(name: String, terms: [String])] = [
        ("Fragrance", ["fragrance", "parfum", "perfume", "essential oil"]),
        ("Fragrance allergens", ["limonene", "linalool", "citronellol", "geraniol", "eugenol", "isoeugenol", "coumarin",
                                 "cinnamal", "hexyl cinnamal", "amyl cinnamal", "citral", "farnesol", "benzyl salicylate",
                                 "benzyl benzoate", "hydroxycitronellal", "alpha-isomethyl ionone", "butylphenyl methylpropional"]),
        ("MI preservative", ["methylisothiazolinone", "methylchloroisothiazolinone", "isothiazolinone"]),
        ("Sulfates (SLS)", ["sodium lauryl sulfate", "sodium laureth sulfate", "ammonium lauryl sulfate",
                            "ammonium laureth sulfate", "sodium lauryl sulphate", "sodium laureth sulphate"]),
        ("Cocamidopropyl betaine", ["cocamidopropyl betaine"]),
        ("Formaldehyde releaser", ["dmdm hydantoin", "quaternium-15", "imidazolidinyl urea", "diazolidinyl urea",
                                   "bronopol", "bromo-2-nitropropane", "sodium hydroxymethylglycinate", "formaldehyde"]),
        ("Lanolin", ["lanolin", "wool alcohol", "wool wax"]),
        ("Propylene glycol", ["propylene glycol"]),
        ("Drying alcohol", ["alcohol denat", "denatured alcohol", "sd alcohol"]),
        ("Tea tree oil", ["tea tree", "melaleuca alternifolia"]),
        ("Balsam of Peru", ["balsam of peru", "myroxylon pereirae"]),
        ("Benzalkonium chloride", ["benzalkonium chloride"]),
        ("Colophony", ["colophonium", "colophony", "rosin"]),
        ("Propolis", ["propolis"]),
    ]

    static var groupNames: [String] { groups.map(\.name) }

    static func check(_ texts: [String]) -> LabelScanResult {
        let raw = texts.joined(separator: " ")
        // Undo OCR line-break hyphenation, unify spacing and case.
        let text = raw
            .replacingOccurrences(of: "-\n", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        var findings: [LabelScanResult.Finding] = []
        for group in groups {
            let hits = group.terms.filter { text.contains($0) }
            if !hits.isEmpty { findings.append(.init(name: group.name, matched: hits)) }
        }
        let words = text.split(separator: " ").count
        return LabelScanResult(findings: findings, wordCount: words)
    }

    /// A typical scented body-wash label (used by "Try a sample label" where there is no camera).
    static let sampleLabel = [
        "INGREDIENTS: Aqua (Water), Sodium Laureth Sulfate, Cocamidopropyl Betaine, Glycerin,",
        "Sodium Chloride, Parfum (Fragrance), Citric Acid, Sodium Benzoate, Limonene, Linalool,",
        "Hexyl Cinnamal, Methylisothiazolinone, CI 42090.",
    ]
}

// MARK: - Scanner screen

/// Full-screen label scanner. Live text (VisionKit) when the device has a camera; otherwise a
/// photo of the label (Vision OCR) or a sample label.
struct LabelScanView: View {
    var onResult: (LabelScanResult) -> Void
    @Environment(\.dismiss) private var dismiss
    /// nil while the camera permission is being asked (first use).
    @State private var live: Bool? = LabelScanView.initialMode()

    var body: some View {
        Group {
            switch live {
            case .some(true): LiveScanScreen(finish: finish, cancel: { dismiss() })
            case .some(false): PhotoScanScreen(finish: finish, cancel: { dismiss() })
            case .none: Color.black.ignoresSafeArea()
            }
        }
        .preferredColorScheme(.light)
        .task {
            guard live == nil else { return }
            // Ask for the camera first, then pick live scanning or the photo fallback.
            _ = await AVCaptureDevice.requestAccess(for: .video)
            live = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        }
    }

    private static func initialMode() -> Bool? {
        guard DataScannerViewController.isSupported else { return false }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { return nil }
        return DataScannerViewController.isAvailable
    }

    private func finish(_ result: LabelScanResult) {
        onResult(result)
        dismiss()
    }
}

/// Yellow frame header shared by both scanner states.
private struct ScanTopBar: View {
    var subtitle: String
    var cancel: () -> Void
    var body: some View {
        TopBar(title: "Scan a label", subtitle: subtitle) {
            Button(action: cancel) {
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
}

// MARK: Live (camera)

private struct LiveScanScreen: View {
    var finish: (LabelScanResult) -> Void
    var cancel: () -> Void
    @State private var seen: [String] = []
    @State private var result = IrritantCheck.check([])

    var body: some View {
        VStack(spacing: 0) {
            ScanTopBar(subtitle: "Point at the ingredients", cancel: cancel)
            LiveTextScanner { texts in
                // Keep everything read so far: a label rarely fits in one frame.
                var all = seen
                for t in texts where !all.contains(t) { all.append(t) }
                guard all.count != seen.count else { return }
                seen = all
                let next = IrritantCheck.check(all)
                if next.findings.count > result.findings.count { Haptics.tap() }
                withAnimation(Twin.Motion.bouncy) { result = next }
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                ScanFindingsPanel(result: result, live: true) { finish(result) }
                    .padding(Twin.Space.l)
            }
        }
        .background(Color.black)
    }
}

private struct LiveTextScanner: UIViewControllerRepresentable {
    var onTexts: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .accurate,
                                           recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
                                           isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        DispatchQueue.main.async { try? vc.startScanning() }
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.onTexts = onTexts
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTexts: onTexts) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onTexts: ([String]) -> Void
        init(onTexts: @escaping ([String]) -> Void) { self.onTexts = onTexts }

        private func report(_ items: [RecognizedItem]) {
            let texts = items.compactMap { item -> String? in
                if case .text(let text) = item { return text.transcript }
                return nil
            }
            onTexts(texts)
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) { report(allItems) }
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) { report(allItems) }
    }
}

// MARK: Photo (no camera)

private struct PhotoScanScreen: View {
    var finish: (LabelScanResult) -> Void
    var cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Entrance rise (fade only with Reduce Motion).
    private var rise: CGFloat { reduceMotion ? 0 : 14 }
    @State private var pick: PhotosPickerItem?
    @State private var reading = false
    @State private var result: LabelScanResult?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            ScanTopBar(subtitle: "From a photo", cancel: cancel)
            ScrollView {
                VStack(alignment: .leading, spacing: Twin.Space.m) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Label check")
                        Text("Read the ingredients, flag common irritants.")
                            .font(Twin.Typeface.sans(20, .bold))
                            .tracking(-0.3)
                            .foregroundStyle(Twin.Palette.ink)
                        Text("Live scanning needs the iPhone camera. Pick a clear photo of the ingredients list instead. Nothing leaves your phone.")
                            .font(Twin.Typeface.sans(15))
                            .foregroundStyle(Twin.Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .twinCard()
                    .riseIn(0.05, distance: rise)

                    PhotosPicker(selection: $pick, matching: .images) {
                        Label("Choose a photo of a label", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink, height: 52))
                    .riseIn(0.12, distance: rise)

                    Button(action: useSample) {
                        Label("Try a sample body-wash label", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(TwinButtonStyle(fill: Twin.Palette.paper, height: 50))
                    .riseIn(0.18, distance: rise)

                    if reading {
                        HStack(spacing: 10) {
                            PixelSpinner()
                            Text("Reading the label…").font(Twin.Typeface.sans(15)).foregroundStyle(Twin.Palette.inkMuted)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Twin.Palette.fill, in: RoundedRectangle(cornerRadius: Twin.Radius.card))
                        .transition(.opacity)
                    }
                    if failed {
                        Text("Couldn't find any text in that photo. Try a sharper, closer shot of the ingredients.")
                            .font(Twin.Typeface.sans(14))
                            .foregroundStyle(Twin.Palette.inkMuted)
                            .padding(.leading, 10)
                            .overlay(alignment: .leading) { Rectangle().fill(Twin.Palette.orange).frame(width: 2) }
                            .transition(.opacity)
                    }
                    if let result {
                        ScanFindingsPanel(result: result, live: false) { finish(result) }
                            .transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "What it looks for")
                            WrapRows(items: IrritantCheck.groupNames.map { ScanTerm(name: $0) }) { term in
                                Text(term.name)
                                    .font(Twin.Typeface.sans(13, .semibold))
                                    .foregroundStyle(Twin.Palette.ink)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .sticker(Twin.Palette.paper)
                            }
                            Text("Common contact irritants in skin care. A match is a hint for Claude, not a diagnosis.")
                                .font(Twin.Typeface.sans(12))
                                .foregroundStyle(Twin.Palette.inkHint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 8)
                        .riseIn(0.26, distance: rise)
                        .transition(.opacity)
                    }
                }
                .padding(Twin.Space.screen)
            }
            .scrollIndicators(.hidden)
        }
        .background(Twin.Palette.paper)
        .onReceive(NotificationCenter.default.publisher(for: .shellDemo)) { note in
            switch note.object as? String {
            case "scan.sample": useSample()
            case "scan.use": if let result { finish(result) }
            default: break
            }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
    }

    private func useSample() {
        let r = IrritantCheck.check(IrritantCheck.sampleLabel)
        Haptics.success()
        withAnimation(Twin.Motion.bouncy) { result = r; failed = false }
    }

    private func read(_ item: PhotosPickerItem) async {
        withAnimation { reading = true; failed = false; result = nil }
        let data = try? await item.loadTransferable(type: Data.self)
        let lines = await OCR.lines(in: data)
        withAnimation(Twin.Motion.bouncy) {
            reading = false
            if lines.isEmpty { failed = true } else { result = IrritantCheck.check(lines) }
        }
        if !lines.isEmpty { Haptics.success() }
    }
}

/// Vision text recognition on a still photo (off the main thread).
private enum OCR {
    static func lines(in data: Data?) async -> [String] {
        guard let data, let image = UIImage(data: data), let cg = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
            do { try handler.perform([request]) } catch { return [] }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Findings

/// Live/finished findings with the "Use this label" action.
private struct ScanFindingsPanel: View {
    let result: LabelScanResult
    let live: Bool
    var use: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: live ? "Reading the label" : "Label check")
                Spacer()
                HStack(spacing: 4) {
                    CountingText(value: Double(result.wordCount), font: Twin.Typeface.mono(11, bold: true), color: Twin.Palette.ink)
                        .animation(.easeOut(duration: 0.4), value: result.wordCount)
                    Text("WORDS").font(Twin.Typeface.meta).foregroundStyle(Twin.Palette.inkHint)
                }
            }
            FindingStickers(result: result, live: live)
            Button(action: use) {
                Label("Use this label", systemImage: "checkmark")
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink, height: 50))
            .disabled(result.wordCount < 3)
            .opacity(result.wordCount < 3 ? 0.5 : 1)
            Text("Not a diagnosis. Flags common irritants so Claude can weigh this product.")
                .font(Twin.Typeface.sans(12))
                .foregroundStyle(Twin.Palette.inkHint)
        }
        .twinCard(fill: Twin.Palette.paper, border: Twin.Palette.ink, borderWidth: Twin.Stroke.ink)
    }
}

/// Orange stickers for each irritant group found, or a lime "nothing found".
private struct FindingStickers: View {
    let result: LabelScanResult
    let live: Bool
    var body: some View {
        if result.findings.isEmpty {
            if live && result.wordCount < 3 {
                Text("Hold the label steady, ingredients in view.")
                    .font(Twin.Typeface.sans(14))
                    .foregroundStyle(Twin.Palette.inkMuted)
            } else {
                Sticker(text: "No common irritants found", icon: "checkmark", fill: Twin.Palette.lime)
            }
        } else {
            WrapRows(items: result.findings) { f in
                Sticker(text: f.name, icon: "exclamationmark.triangle.fill", fill: Twin.Palette.orange)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
    }
}

/// The scan summary shown in the tag sheet after a scan.
struct ScanResultCard: View {
    let result: LabelScanResult
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("🧴").font(.system(size: 15))
                    .frame(width: 28, height: 28)
                    .sticker(Twin.Palette.pink)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Label scanned")
                        .font(Twin.Typeface.sans(15, .bold))
                        .foregroundStyle(Twin.Palette.ink)
                    Text("ADDED AS A NEW PRODUCT")
                        .font(Twin.Typeface.meta)
                        .foregroundStyle(Twin.Palette.inkHint)
                }
                Spacer()
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Twin.Palette.inkMuted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Remove scan")
            }
            FindingStickers(result: result, live: false)
        }
        .twinCard(fill: Twin.Palette.cream, padding: 14)
    }
}

private struct ScanTerm: Identifiable {
    let name: String
    var id: String { name }
}

/// Minimal wrapping row for a few stickers.
private struct WrapRows<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder var content: (Item) -> Content
    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(items) { content($0) }
        }
    }
}

private struct WrapLayout: Layout {
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
