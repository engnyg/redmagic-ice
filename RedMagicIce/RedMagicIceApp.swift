import SwiftUI

@main
struct RedMagicIceApp: App {
    @StateObject private var ble = CoolerBLEManager()
    @StateObject private var light = LightController()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(light)
                .preferredColorScheme(.dark)
                .onAppear { light.attach(ble) }
        }
    }
}
