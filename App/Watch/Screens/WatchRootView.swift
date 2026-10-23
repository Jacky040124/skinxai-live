import SwiftUI
import EczemaKit

/// Ring and Recent are vertical pages (Digital Crown). The scratch alert replaces them while it is
/// up (so the system page indicator goes away too). One title row, on the clock's line, serves all
/// of them and cross-fades between "Twin" and "Recent", like a watchOS navigation title.
struct WatchRootView: View {
    @EnvironmentObject var model: WatchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let ins = geo.safeAreaInsets
            let clockRow = max(30, ins.top)
            ZStack(alignment: .topLeading) {
                Group {
                    if let alert = model.alert {
                        PageFrame(bottomMargin: 10) {
                            ScratchAlertView(alert: alert)
                        }
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity,
                                                                          removal: .scale(scale: 0.84).combined(with: .opacity)))
                        .zIndex(1)
                    } else {
                        TabView(selection: $model.page) {
                            PageFrame(bottomMargin: 10) { RingScreen() }
                                .tag(WatchModel.Page.ring)
                            PageFrame { RecentScreen() }
                                .tag(WatchModel.Page.recent)
                        }
                        .tabViewStyle(.verticalPage)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 1.08).combined(with: .opacity),
                                                                          removal: .opacity))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)

                WatchTitle(text: title, flash: model.alert == nil ? model.flash : nil,
                           live: model.alert == nil && model.live.isOn)
                    .frame(height: clockRow, alignment: .center)
                    .offset(x: WatchLayout.titleLeading - ins.leading, y: -ins.top)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var title: String {
        model.alert == nil && model.page == .recent ? "Recent" : "Twin"
    }
}

/// A page's content area: from just under the clock row to `bottomMargin` above the bottom edge
/// (the system's safe area keeps a lot more room for a navigation bar and corner toolbar than
/// these pages need). The title is drawn once by `WatchRootView`.
struct PageFrame<Content: View>: View {
    var bottomMargin: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let ins = geo.safeAreaInsets
            let fullW = geo.size.width + ins.leading + ins.trailing
            let fullH = geo.size.height + ins.top + ins.bottom
            let contentTop = max(30, ins.top) / 2 + WatchLayout.belowClock
            content()
                .frame(width: fullW, height: max(0, fullH - contentTop - bottomMargin))
                .offset(x: -ins.leading, y: contentTop - ins.top)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

enum WatchLayout {
    /// Content starts this far below the middle of the clock row.
    static let belowClock: CGFloat = 14
    static let titleLeading: CGFloat = 16
}
