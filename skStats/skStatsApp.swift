import SwiftUI

@main
struct skStatsApp: App {
    @StateObject private var monitor = SystemMonitor()
    
    var body: some Scene {
        MenuBarExtra("skStats", systemImage: "gauge.medium") {
            ContentView(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
        

    }
}
