import SwiftUI

@main
struct RedMagicIceApp: App {
    @StateObject private var ble = CoolerBLEManager()
    @StateObject private var light = LightController()
    @StateObject private var appearance = AppearanceController()
    @StateObject private var live = LiveActivityController()
    @StateObject private var memory = MemoryController()
    @StateObject private var auto = AutoController()
    @StateObject private var updates = UpdateChecker()
    @StateObject private var shutdown = ShutdownTimerController()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(light)
                .environmentObject(appearance)
                .environmentObject(live)
                .environmentObject(memory)
                .environmentObject(auto)
                .environmentObject(updates)
                .environmentObject(shutdown)
                .preferredColorScheme(.dark)
                .onAppear { light.attach(ble); live.attach(ble); auto.attach(ble); shutdown.attach(ble); memory.attach(ble, light, auto) }
                .task { await updates.check() }
        }
    }
}
