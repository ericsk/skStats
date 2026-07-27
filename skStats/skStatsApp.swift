import SwiftUI

@main
struct skStatsApp: App {
    @StateObject private var monitor = SystemMonitor()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            HStack(spacing: 8) {
                if let stats = monitor.currentStats {
                    if monitor.showMenuBarCPU {
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                            if monitor.showMenuBarText {
                                Text(FormatUtils.formatPercentage(stats.totalCPULoad))
                            }
                        }
                    }
                    if monitor.showMenuBarGPU {
                        HStack(spacing: 3) {
                            Image(systemName: "square.grid.3x3.fill")
                            if monitor.showMenuBarText {
                                Text(FormatUtils.formatPercentage(stats.gpuLoad))
                            }
                        }
                    }
                    if monitor.showMenuBarMemory {
                        HStack(spacing: 3) {
                            Image(systemName: "memorychip")
                            if monitor.showMenuBarText {
                                Text(FormatUtils.formatPercentage(stats.memoryUsed / monitor.memoryTotal))
                            }
                        }
                    }
                    if monitor.showMenuBarNetwork {
                        HStack(spacing: 3) {
                            Image(systemName: "network")
                            if monitor.showMenuBarText {
                                Text("↑\(FormatUtils.formatCompactRate(stats.netUp)) ↓\(FormatUtils.formatCompactRate(stats.netDown))")
                            }
                        }
                    }
                    if monitor.showMenuBarDisk {
                        HStack(spacing: 3) {
                            Image(systemName: "internaldrive")
                            if monitor.showMenuBarText {
                                Text("R:\(FormatUtils.formatCompactRate(stats.diskRead)) W:\(FormatUtils.formatCompactRate(stats.diskWrite))")
                            }
                        }
                    }
                    if monitor.hasBattery && monitor.showMenuBarBattery {
                        HStack(spacing: 3) {
                            Image(systemName: batteryIcon(level: stats.batteryLevel, isCharging: stats.batteryIsCharging))
                            if monitor.showMenuBarText {
                                Text(FormatUtils.formatPercentage(stats.batteryLevel))
                            }
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
