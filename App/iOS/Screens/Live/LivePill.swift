import SwiftUI

/// The cyan "● Live" sticker next to the avatar in Today's top bar (prototype `.livepill`), shown
/// only while the watch is tracking sleep. Tapping it turns the phone sideways into the live
/// monitor; Done (or the watch's Stop) turns it back.
///
/// When hidden it takes no room at all, so the avatar keeps its place:
///
///     HStack(spacing: 10) { LivePill(); UserAvatar() }
struct LivePill: View {
    @ObservedObject private var session = LiveSession.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if session.tracking {
            Button {
                // The monitor covers everything, so Today is still underneath when it closes.
                LiveMonitorPresenter.shared.open()
            } label: {
                HStack(spacing: 6) {
                    LiveDot()
                    Text("Live").font(Twin.Typeface.sans(13, .bold))
                }
                .foregroundStyle(Twin.Palette.ink)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .sticker(Twin.Palette.cyan)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .offset(y: 10).combined(with: .opacity),
                removal: .opacity.combined(with: .scale(scale: 0.9))))
            .accessibilityLabel("Live sleep tracking")
            .accessibilityHint("Opens the live monitor")
        }
    }
}
