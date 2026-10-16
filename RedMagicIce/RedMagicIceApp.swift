import SwiftUI

@main
struct RedMagicIceApp: App {
    @StateObject private var ble = CoolerBLEManager()
    @StateObject private var light = LightController()
    @StateObject private var appearance = AppearanceController()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(light)
                .environmentObject(appearance)
                .preferredColorScheme(.dark)
                .onAppear { light.attach(ble) }
        }
    }
}
