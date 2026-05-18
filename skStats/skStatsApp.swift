import SwiftUI

@main
struct skStatsApp: App {
    @StateObject private var monitor = SystemMonitor()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                if let stats = monitor.currentStats {
                    switch monitor.showMenuBarMode {
                    case .cpu:
                        Image(systemName: "cpu")
                        if monitor.showMenuBarText {
                            Text("\(Int(stats.totalCPULoad * 100))%")
                        }
                    case .gpu:
                        Image(systemName: "cpu.fill")
                        if monitor.showMenuBarText {
                            Text("\(Int(stats.gpuLoad * 100))%")
                        }
                    case .memory:
                        Image(systemName: "memorychip")
                        if monitor.showMenuBarText {
                            Text(String(format: "%.0f%%", (stats.memoryUsed / monitor.memoryTotal) * 100))
                        }
                    case .network:
                        Image(systemName: "network")
                        if monitor.showMenuBarText {
                            Text("↑\(FormatUtils.formatBytes(stats.netUp)) ↓\(FormatUtils.formatBytes(stats.netDown))")
                        }
                    case .disk:
                        Image(systemName: "externaldrive")
                        if monitor.showMenuBarText {
                            Text("R\(FormatUtils.formatBytes(stats.diskRead)) W\(FormatUtils.formatBytes(stats.diskWrite))")
                        }
                    case .battery:
                        Image(systemName: stats.batteryIsCharging ? "battery.100.bolt" : "battery.100")
                        if monitor.showMenuBarText {
                            Text("\(Int(stats.batteryLevel * 100))%")
                        }
                    }
                } else {
                    Image(systemName: "cpu")
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .menuBarExtraStyle(.window)
    }
}
