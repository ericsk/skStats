import SwiftUI

@main
struct skStatsApp: App {
    @StateObject private var monitor = SystemMonitor()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                switch monitor.showMenuBarMode {
                case .cpu:
                    Image(systemName: "cpu")
                    if monitor.showMenuBarText {
                        Text("\(Int(monitor.totalCPULoad * 100))%")
                    }
                case .gpu:
                    Image(systemName: "cpu.fill")
                    if monitor.showMenuBarText {
                        Text("\(Int(monitor.gpuLoad * 100))%")
                    }
                case .memory:
                    Image(systemName: "memorychip")
                    if monitor.showMenuBarText {
                        Text(String(format: "%.0f%%", (monitor.memoryUsed / monitor.memoryTotal) * 100))
                    }
                case .network:
                    Image(systemName: "network")
                    if monitor.showMenuBarText {
                        Text("↑\(FormatUtils.formatBytes(monitor.networkUploadRate)) ↓\(FormatUtils.formatBytes(monitor.networkDownloadRate))")
                    }
                case .disk:
                    Image(systemName: "externaldrive")
                    if monitor.showMenuBarText {
                        Text("R\(FormatUtils.formatBytes(monitor.diskReadRate)) W\(FormatUtils.formatBytes(monitor.diskWriteRate))")
                    }
                case .battery:
                    Image(systemName: monitor.batteryIsCharging ? "battery.100.bolt" : "battery.100")
                    if monitor.showMenuBarText {
                        Text("\(Int(monitor.batteryLevel * 100))%")
                    }
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .menuBarExtraStyle(.window)
    }
}
