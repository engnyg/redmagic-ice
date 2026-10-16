import SwiftUI

@main
struct RedMagicIceApp: App {
    @StateObject private var ble = CoolerBLEManager()
    @StateObject private var light = LightController()
    @StateObject private var appearance = AppearanceController()
    @StateObject private var live = LiveActivityController()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(light)
                .environmentObject(appearance)
                .environmentObject(live)
                .preferredColorScheme(.dark)
                .onAppear { light.attach(ble); live.attach(ble) }
        }
    }
}
