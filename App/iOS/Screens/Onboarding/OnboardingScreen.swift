import SwiftUI
import EczemaKit

/// Shows onboarding above the whole app (first launch, `-screen onboarding`, Settings → Replay).
struct OnboardingHost: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ZStack {
            if app.showOnboarding {
                OnboardingScreen()
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.22), value: app.showOnboarding)
    }
}

/// Three pages: (1) the watch writes a scratch diary, (2) what is tracked automatically,
/// (3) permissions + watch status. The yellow frame opens out of the top bar on entry and folds
/// back into it on exit, so the app appears right under it.
struct OnboardingScreen: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var dots

    /// `-onboardingPage 2` opens a page directly (screenshots).
    @State private var page = min(max(UserDefaults.standard.integer(forKey: "onboardingPage"), 0), 2)
    @State private var drag: CGFloat = 0
    @State private var phase: Phase = .closed
    @State private var barHeight: CGFloat = 74

    enum Phase { case closed, open, leaving }
    private let count = 3

    private let copy: [OnboardingCopy] = [
        OnboardingCopy(eyebrow: "Your diary",
             title: "Your skin keeps a diary. Eczema Twin reads it.",
             body: "Your Apple Watch notices when you scratch, even asleep. Claude looks at what changed before each flare."),
        OnboardingCopy(eyebrow: "Tracked for you",
             title: "Most of the diary writes itself.",
             body: "Scratching from your watch, sleep and stress from Health, humidity, air and pollen from where you are. Tap + only for what's new."),
        OnboardingCopy(eyebrow: "Your choice",
             title: "You decide what it can read.",
             body: "Everything stays on your iPhone. Skip anything you like: the demo story works without it."),
    ]

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let width = proxy.size.width
            let height = proxy.size.height + insets.top + insets.bottom
            screen(width: width, height: height, insets: insets)
                .frame(width: width, height: height)
                .ignoresSafeArea()
        }
        .background(alignment: .top) {
            // Measures the real top-bar height so the frame folds exactly into it.
            TopBar(title: " ", subtitle: " ")
                .hidden()
                .background(GeometryReader { g in
                    Color.clear.onAppear { barHeight = g.size.height }
                })
                .accessibilityHidden(true)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.62, dampingFraction: 0.86).delay(0.05)) {
                phase = .open
            }
        }
        .accessibilityAddTraits(.isModal)
        .onReceive(NotificationCenter.default.publisher(for: .shellDemo)) { note in
            guard note.object as? String == "onboarding.next" else { return }
            if page < count - 1 { go(to: page + 1) } else { finish() }
        }
    }

    // MARK: Layout

    private func screen(width: CGFloat, height: CGFloat, insets: EdgeInsets) -> some View {
        let stageHeight = max(300, min(height * 0.57, height - 380))
        let artHeight = stageHeight - insets.top - 44
        let open = phase == .open
        return ZStack(alignment: .top) {
            Twin.Palette.paper
                .opacity(phase == .leaving ? 0 : 1)

            // The frame.
            Twin.Palette.frame
                .overlay(alignment: .bottom) { Rectangle().fill(Twin.Palette.seam).frame(height: 1) }
                .frame(height: open ? stageHeight : insets.top + barHeight)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 0) {
                Color.clear.frame(height: insets.top)
                header.frame(height: 44)
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { i in
                        column(i, width: width, artHeight: artHeight)
                            .frame(width: width)
                    }
                }
                .frame(width: width, alignment: .leading)
                .offset(x: -CGFloat(page) * width + drag)
                .contentShape(Rectangle())
                .gesture(swipe(width: width))
                Spacer(minLength: 0)
            }
            .opacity(open ? 1 : 0)

            controls
                .padding(.horizontal, 24)
                .padding(.bottom, insets.bottom + 14)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(open ? 1 : 0)
                .offset(y: open || reduceMotion ? 0 : 24)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                // Two rings: you and your twin.
                ZStack {
                    Circle().strokeBorder(Twin.Palette.ink, lineWidth: 2.2)
                        .frame(width: 15, height: 15)
                        .offset(x: -4.5)
                    Circle().fill(Twin.Palette.orange)
                        .overlay(Circle().strokeBorder(Twin.Palette.ink, lineWidth: 2.2))
                        .frame(width: 15, height: 15)
                        .offset(x: 4.5)
                }
                .frame(width: 24, height: 16)
                Text("Eczema Twin")
                    .font(Twin.Typeface.sans(17, .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Twin.Palette.ink)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if page < count - 1 {
                Button {
                    go(to: count - 1)
                } label: {
                    Text("Skip")
                        .font(Twin.Typeface.sans(15, .semibold))
                        .foregroundStyle(Twin.Palette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .animation(Twin.Motion.spring, value: page)
    }

    private func column(_ i: Int, width: CGFloat, artHeight: CGFloat) -> some View {
        let progress = CGFloat(page) - drag / max(1, width)
        let delta = CGFloat(i) - progress
        let active = page == i && phase == .open
        return VStack(alignment: .leading, spacing: 0) {
            art(i, active: active)
                .scaleEffect(artScale(width: width, height: artHeight))
                .frame(width: width, height: artHeight)
                .offset(x: reduceMotion ? 0 : delta * width * 0.28)
                .opacity(1 - min(1, abs(delta)) * 0.5)
                .clipped()
            PageText(copy: copy[i], index: i, count: count, active: active)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
    }

    @ViewBuilder private func art(_ i: Int, active: Bool) -> some View {
        switch i {
        case 0: WatchDiaryArt(active: active)
        case 1: AutoTrackedArt(active: active)
        default: PermissionCards(active: active)
        }
    }

    /// The illustrations are drawn at about 370 × 340 pt and scaled down on small phones.
    private func artScale(width: CGFloat, height: CGFloat) -> CGFloat {
        min(1, (width - 32) / 372, (height - 12) / 336)
    }

    private var controls: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    Button { go(to: i) } label: {
                        ZStack {
                            if i == page {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Twin.Palette.yellow)
                                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                                    .matchedGeometryEffect(id: "dot", in: dots)
                                    .frame(width: 26, height: 10)
                            } else {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Twin.Palette.ink.opacity(0.18))
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Page \(i + 1) of \(count)")
                    .accessibilityAddTraits(i == page ? [.isSelected] : [])
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.72), value: page)
            Spacer()
            Button {
                if page < count - 1 { go(to: page + 1) } else { finish() }
            } label: {
                HStack(spacing: 8) {
                    Text(page < count - 1 ? "Next" : "Start")
                        .contentTransition(.interpolate)
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                }
                .frame(minWidth: 108)
                .animation(Twin.Motion.spring, value: page)
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink, height: 52, fullWidth: false))
        }
    }

    // MARK: Paging

    private var pageSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.5, dampingFraction: 0.86)
    }

    private func go(to target: Int) {
        let t = min(max(target, 0), count - 1)
        guard t != page else { return }
        Haptics.tap()
        withAnimation(pageSpring) { page = t; drag = 0 }
    }

    private func swipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                var t = v.translation.width
                if (page == 0 && t > 0) || (page == count - 1 && t < 0) { t /= 3 }   // rubber band at the ends
                drag = t
            }
            .onEnded { v in
                let predicted = v.predictedEndTranslation.width
                var target = page
                if predicted < -width * 0.35 || v.translation.width < -width * 0.25 { target = page + 1 }
                if predicted > width * 0.35 || v.translation.width > width * 0.25 { target = page - 1 }
                target = min(max(target, 0), count - 1)
                if target != page { Haptics.tap() }
                withAnimation(pageSpring) { page = target; drag = 0 }
            }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: ShellServices.Keys.didOnboard)
        Haptics.success()
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.5, dampingFraction: 0.9)) {
            phase = .leaving
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.3 : 0.4)) {
            app.showOnboarding = false
        }
    }
}

private struct OnboardingCopy {
    let eyebrow: String
    let title: String
    let body: String
}

/// Eyebrow, title and body of one page; they rise in when the page becomes active.
private struct PageText: View {
    let copy: OnboardingCopy
    let index: Int
    let count: Int
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let c = copy
        VStack(alignment: .leading, spacing: 10) {
            Text("\(index + 1) / \(count) · \(c.eyebrow.uppercased())")
                .font(Twin.Typeface.eyebrow)
                .tracking(0.8)
                .foregroundStyle(Twin.Palette.inkHint)
                .modifier(Rise(shown: shown, delay: 0, reduceMotion: reduceMotion))
            Text(c.title)
                .font(Twin.Typeface.sans(30, .bold))
                .tracking(-0.9)
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
                .modifier(Rise(shown: shown, delay: 0.06, reduceMotion: reduceMotion))
            Text(c.body)
                .font(Twin.Typeface.sans(16))
                .lineSpacing(3)
                .foregroundStyle(Twin.Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(Rise(shown: shown, delay: 0.12, reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: active, initial: true) { _, isActive in
            if isActive {
                shown = false
                withAnimation { shown = true }
            }
        }
    }
}

private struct Rise: ViewModifier {
    let shown: Bool
    let delay: Double
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation(shown ? Twin.Motion.spring.delay(0.12 + delay) : nil, value: shown)
    }
}
