import SwiftUI

/// Raft-style phone tab bar: the selected icon sits in a yellow sticker that slides between tabs.
struct TwinTabBar: View {
    @EnvironmentObject var app: AppState
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                let on = app.tab == tab
                Button { app.select(tab) } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if on {
                                RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
                                    .fill(Twin.Palette.yellow)
                                    .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
                                        .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                                    .matchedGeometryEffect(id: "sticker", in: ns)
                            }
                            Image(systemName: tab.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(on ? Twin.Palette.ink : Twin.Palette.inkMuted)
                                .symbolEffect(.bounce, value: on)
                        }
                        .frame(width: 48, height: 32)
                        Text(tab.title)
                            .font(Twin.Typeface.sans(11, on ? .bold : .medium))
                            .foregroundStyle(on ? Twin.Palette.ink : Twin.Palette.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(alignment: .top) {
            Twin.Palette.paper
                .overlay(alignment: .top) { Rectangle().fill(Twin.Palette.seam).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(Twin.Motion.spring, value: app.tab)
    }
}
