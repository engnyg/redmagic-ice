import SwiftUI

@main
struct RedMagicIceApp: App {
    @StateObject private var ble = CoolerBLEManager()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(ble) }
    }
}
