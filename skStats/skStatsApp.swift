import SwiftUI

@main
struct skStatsApp: App {
    @StateObject private var monitor = SystemMonitor()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            HStack(spacing: 5) {
                if let stats = monitor.currentStats {
                    switch monitor.showMenuBarMode {
                    case .cpu:
                        Image(systemName: "cpu")
                        if monitor.showMenuBarText {
                            Text(FormatUtils.formatPercentage(stats.totalCPULoad))
                        }
                    case .gpu:
                        Image(systemName: "square.grid.3x3.fill")
                        if monitor.showMenuBarText {
                            Text(FormatUtils.formatPercentage(stats.gpuLoad))
                        }
                    case .memory:
                        Image(systemName: "memorychip")
                        if monitor.showMenuBarText {
                            Text(FormatUtils.formatPercentage(stats.memoryUsed / monitor.memoryTotal))
                        }
                    case .network:
                        Image(systemName: "network")
                        if monitor.showMenuBarText {
                            Text("↑\(FormatUtils.formatRate(stats.netUp)) ↓\(FormatUtils.formatRate(stats.netDown))")
                        }
                    case .disk:
                        Image(systemName: "internaldrive")
                        if monitor.showMenuBarText {
                            Text("R:\(FormatUtils.formatRate(stats.diskRead)) W:\(FormatUtils.formatRate(stats.diskWrite))")
                        }
                    case .battery:
                        Image(systemName: batteryIcon(level: stats.batteryLevel, isCharging: stats.batteryIsCharging))
                        if monitor.showMenuBarText {
                            Text(FormatUtils.formatPercentage(stats.batteryLevel))
                        }
                    }
                } else {
                    Image(systemName: "cpu")
                }
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .menuBarExtraStyle(.window)
    }
    
    private func batteryIcon(level: Double, isCharging: Bool) -> String {
        if isCharging { return "battery.100.bolt" }
        if level < 0.1 { return "battery.0" }
        if level < 0.3 { return "battery.25" }
        if level < 0.6 { return "battery.50" }
        if level < 0.9 { return "battery.75" }
        return "battery.100"
    }
}
