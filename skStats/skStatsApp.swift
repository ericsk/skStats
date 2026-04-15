import SwiftUI

@main
struct skStatsApp: App {
    @StateObject private var monitor = SystemMonitor()
    
    var body: some Scene {
        MenuBarExtra("skStats", systemImage: "chart.xyaxis.line") {
            ContentView(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView(monitor: monitor)
        }
    }
}
