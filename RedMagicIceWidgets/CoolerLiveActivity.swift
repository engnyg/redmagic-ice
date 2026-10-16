import WidgetKit
import SwiftUI
import ActivityKit

@main
struct RedMagicIceWidgets: WidgetBundle {
    var body: some Widget { CoolerLiveActivity() }
}

struct CoolerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CoolerActivityAttributes.self) { context in
            LockScreenView(name: context.attributes.deviceName, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.45))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(s.modeTitle, systemImage: s.running ? "fanblades.fill" : "fanblades")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(s.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(s.temperatureText).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        stat("轉速", s.rpm.map { "\($0) RPM" })
                        Spacer()
                        stat("功率", s.powerW.map { "\($0) W" })
                        Spacer()
                        stat("裝置", context.attributes.deviceName)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "fanblades.fill").foregroundStyle(s.tint)
            } compactTrailing: {
                Text(s.temperatureText).font(.system(.footnote, design: .rounded).weight(.semibold)).foregroundStyle(.white)
            } minimal: {
                Image(systemName: "fanblades.fill").foregroundStyle(s.tint)
            }
            .keylineTint(s.tint)
        }
    }

    private func stat(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.6))
            Text(value ?? "--").font(.footnote.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
        }
    }
}

struct LockScreenView: View {
    let name: String
    let state: CoolerActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: state.running ? "fanblades.fill" : "fanblades")
                .font(.system(size: 30)).foregroundStyle(state.tint).frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.footnote).foregroundStyle(.white.opacity(0.7))
                Text(state.modeTitle).font(.headline).foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.temperatureText).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text("\(state.rpm.map(String.init) ?? "--") RPM · \(state.powerW.map(String.init) ?? "--") W")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(16)
    }
}
