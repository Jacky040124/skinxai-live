import SwiftUI
import EczemaKit

/// PLACEHOLDER — replaced by the agent that owns App/Watch.
struct WatchRootView: View {
    @EnvironmentObject var model: WatchModel
    var body: some View {
        let today = model.dataset.today
        VStack(spacing: 6) {
            ZStack {
                RingView(progress: min(1, (today?.scratchMinutes ?? 0) / 60), lineWidth: 12,
                         color: Twin.Palette.orange, track: Twin.Palette.nightTrack)
                CountUp(value: today?.scratchMinutes ?? 0, font: Twin.Typeface.sans(30, .bold), color: .white)
            }
            .frame(width: 110, height: 110)
            Text("MIN TODAY").font(Twin.Typeface.meta).foregroundStyle(Twin.Palette.nightMuted)
        }
        .sheet(isPresented: $model.showPrompt) {
            Text("Were you scratching?").font(Twin.Typeface.headline)
        }
    }
}
