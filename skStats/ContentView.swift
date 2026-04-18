import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var isShowingSettings = false
    
    var body: some View {
        if isShowingSettings {
            VStack {
                HStack {
                    Button(action: {
                        isShowingSettings = false
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    Text("Settings").font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                SettingsView(monitor: monitor)
            }
            .frame(width: 320)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("skStats").font(.headline)
                    Spacer()
                    Button(action: {
                        isShowingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            
                if monitor.showCPU { CPUDashboard(monitor: monitor) }
                if monitor.showGPU { GPUDashboard(monitor: monitor) }
                if monitor.showMemory { MemoryDashboard(monitor: monitor) }
                if monitor.showDisk { DiskDashboard(monitor: monitor) }
                if monitor.showNetwork { NetworkDashboard(monitor: monitor) }
                if monitor.showTopCPU && !monitor.topCPU.isEmpty { TopCPUDashboard(monitor: monitor) }
                if monitor.showTopMemory && !monitor.topMemory.isEmpty { TopMemoryDashboard(monitor: monitor) }
            }
            .padding()
            .frame(width: 320)
        }
    }
}

// MARK: - Subcomponents

struct CPUDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("CPU Load").font(.subheadline).bold()
            let count = monitor.cpuLoadPerCore.count
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(8, max(1, count)))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(0..<count, id: \.self) { index in
                    VStack(spacing: 2) {
                        Text("\(Int(monitor.cpuLoadPerCore[index] * 100))%").font(.system(size: 9))
                        ProgressView(value: monitor.cpuLoadPerCore[index]).progressViewStyle(LinearProgressViewStyle())
                    }
                }
            }
        }
        Divider()
    }
}

struct GPUDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("GPU Load").font(.subheadline).bold()
            HStack {
                Text("\(Int(monitor.gpuLoad * 100))%").font(.system(size: 11))
                ProgressView(value: monitor.gpuLoad).progressViewStyle(LinearProgressViewStyle())
            }
        }
        Divider()
    }
}

struct MemoryDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Memory").font(.subheadline).bold()
            Text(String(format: "Used: %.2f GB / %.2f GB", monitor.memoryUsed / 1_000_000_000, monitor.memoryTotal / 1_000_000_000))
                .font(.caption)
            ProgressView(value: monitor.memoryUsed, total: monitor.memoryTotal)
        }
        Divider()
    }
}

struct DiskDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Disk IO").font(.subheadline).bold()
            Text("R: \(FormatUtils.formatBytes(monitor.diskReadRate))/s  W: \(FormatUtils.formatBytes(monitor.diskWriteRate))/s")
                .font(.caption)
        }
        Divider()
    }
}

struct NetworkDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Network").font(.subheadline).bold()
            Text("↑ \(FormatUtils.formatBytes(monitor.networkUploadRate))/s  ↓ \(FormatUtils.formatBytes(monitor.networkDownloadRate))/s")
                .font(.caption)
        }
        Divider()
    }
}

struct TopCPUDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top CPU Processes").font(.subheadline).bold()
            ForEach(monitor.topCPU) { process in
                HStack {
                    Text(process.name).font(.caption).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(process.value).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        Divider()
    }
}

struct TopMemoryDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top Memory Processes").font(.subheadline).bold()
            ForEach(monitor.topMemory) { process in
                HStack {
                    Text(process.name).font(.caption).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(process.value).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        Divider()
    }
}

// MARK: - Utilities

struct FormatUtils {
    static func formatBytes(_ bytes: Double) -> String {
        if bytes == 0 { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(spacing: 12) {
            GroupBox("Visibility") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show CPU Load", isOn: $monitor.showCPU)
                    Toggle("Show GPU Load", isOn: $monitor.showGPU)
                    Toggle("Show Memory Usage", isOn: $monitor.showMemory)
                    Toggle("Show Disk I/O", isOn: $monitor.showDisk)
                    Toggle("Show Network Speed", isOn: $monitor.showNetwork)
                    Toggle("Show Top CPU Processes", isOn: $monitor.showTopCPU)
                    Toggle("Show Top Memory Processes", isOn: $monitor.showTopMemory)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            
            GroupBox("Update Frequency") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current Interval: \(Int(monitor.updateInterval)) sec")
                    HStack {
                        Text("1s").font(.caption).foregroundColor(.secondary)
                        Slider(value: $monitor.updateInterval, in: 1...10, step: 1.0)
                        Text("10s").font(.caption).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .padding()
        .onChange(of: monitor.showCPU) { _ in monitor.saveSettings() }
        .onChange(of: monitor.showGPU) { _ in monitor.saveSettings() }
        .onChange(of: monitor.showMemory) { _ in monitor.saveSettings() }
        .onChange(of: monitor.showDisk) { _ in monitor.saveSettings() }
        .onChange(of: monitor.showNetwork) { _ in monitor.saveSettings() }
        .onChange(of: monitor.showTopCPU) { _ in monitor.saveSettings() }
        .onChange(of: monitor.showTopMemory) { _ in monitor.saveSettings() }
        .onChange(of: monitor.updateInterval) { _ in
            monitor.saveSettings()
            monitor.startMonitoring()
        }
    }
}
