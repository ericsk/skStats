import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("skStats").font(.headline)
            Divider()
            
            if monitor.showCPU {
                VStack(alignment: .leading) {
                    Text("CPU Load")
                        .font(.subheadline)
                        .bold()
                    HStack(spacing: 4) {
                        ForEach(0..<monitor.cpuLoadPerCore.count, id: \.self) { index in
                            VStack {
                                Text("\(Int(monitor.cpuLoadPerCore[index] * 100))%")
                                    .font(.system(size: 9))
                                ProgressView(value: monitor.cpuLoadPerCore[index])
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .frame(width: 25)
                            }
                        }
                    }
                }
                Divider()
            }
            
            if monitor.showMemory {
                VStack(alignment: .leading) {
                    Text("Memory")
                        .font(.subheadline)
                        .bold()
                    Text(String(format: "Used: %.2f GB / %.2f GB", monitor.memoryUsed / 1_000_000_000, monitor.memoryTotal / 1_000_000_000))
                        .font(.caption)
                    ProgressView(value: monitor.memoryUsed, total: monitor.memoryTotal)
                }
                Divider()
            }
            
            if monitor.showDisk {
                VStack(alignment: .leading) {
                    Text("Disk IO")
                        .font(.subheadline)
                        .bold()
                    Text("R: \(formatBytes(monitor.diskReadRate))/s  W: \(formatBytes(monitor.diskWriteRate))/s")
                        .font(.caption)
                }
                Divider()
            }
            
            if monitor.showNetwork {
                VStack(alignment: .leading) {
                    Text("Network")
                        .font(.subheadline)
                        .bold()
                    Text("↑ \(formatBytes(monitor.networkUploadRate))/s  ↓ \(formatBytes(monitor.networkDownloadRate))/s")
                        .font(.caption)
                }
                Divider()
            }
            
            HStack {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 320)
    }
    
    func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct SettingsView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        Form {
            Toggle("Show CPU Load", isOn: $monitor.showCPU)
            Toggle("Show Memory Usage", isOn: $monitor.showMemory)
            Toggle("Show Disk I/O", isOn: $monitor.showDisk)
            Toggle("Show Network Speed", isOn: $monitor.showNetwork)
        }
        .padding()
        .frame(width: 250, height: 180)
        .onChange(of: monitor.showCPU) { _ in monitor.saveSettings() }
        .onChange(of: monitor.showMemory) { _ in monitor.saveSettings() }
        .onChange(of: monitor.showDisk) { _ in monitor.saveSettings() }
        .onChange(of: monitor.showNetwork) { _ in monitor.saveSettings() }
    }
}
