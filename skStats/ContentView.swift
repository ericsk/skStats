import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var isShowingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isShowingSettings {
                settingsHeader
                SettingsView(monitor: monitor)
                    .transition(.move(edge: .trailing))
            } else {
                mainHeader
                VStack(alignment: .leading, spacing: 12) {
                    if let stats = monitor.currentStats {
                        if monitor.showCPU { CPUDashboard(cpuLoadPerCore: stats.cpuLoadPerCore) }
                        if monitor.showGPU { GPUDashboard(gpuLoad: stats.gpuLoad) }
                        if monitor.showMemory { MemoryDashboard(memoryUsed: stats.memoryUsed, memoryTotal: monitor.memoryTotal, memoryPressure: stats.memoryPressure, memorySwap: stats.memorySwap, showAdvancedMemory: monitor.showAdvancedMemory) }
                        if monitor.showBattery { BatteryDashboard(batteryLevel: stats.batteryLevel, batteryIsCharging: stats.batteryIsCharging, batteryPowerUsage: stats.batteryPowerUsage, batteryAdapterWattage: stats.batteryAdapterWattage, batteryCycleCount: stats.batteryCycleCount, batteryHealth: stats.batteryHealth) }
                        if monitor.showDisk || monitor.showNetwork {
                            HStack(alignment: .top, spacing: 12) {
                                if monitor.showDisk {
                                    DiskDashboard(diskReadRate: stats.diskRead, diskWriteRate: stats.diskWrite)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                if monitor.showNetwork {
                                    NetworkDashboard(networkDownloadRate: stats.netDown, networkUploadRate: stats.netUp)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                            }
                        }
                        if monitor.showSystemInfo { SystemInfoDashboard(diskFree: stats.diskFree, diskTotal: stats.diskTotal, uptime: stats.uptime) }
                        if monitor.showTopCPU && !stats.topCPU.isEmpty { TopCPUDashboard(topCPU: stats.topCPU) }
                        if monitor.showTopMemory && !stats.topMemory.isEmpty { TopMemoryDashboard(topMemory: stats.topMemory) }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                .transition(.move(edge: .leading))
            }
        }
        .frame(width: 320)
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isShowingSettings)
        .onAppear { monitor.isPopoverVisible = true }
        .onDisappear { monitor.isPopoverVisible = false }
    }
    
    private var mainHeader: some View {
        HStack {
            Text("skStats")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.accentColor)
            Spacer()
            Button { isShowingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
    
    private var settingsHeader: some View {
        HStack {
            Button { isShowingSettings = false } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Settings")
                .font(.system(.headline, design: .rounded))
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
}

// 輔助：背景模糊效果
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Subcomponents

struct CPUDashboard: View {
    let cpuLoadPerCore: [Double]
    
    var body: some View {
        DashboardSection(title: "CPU Load", icon: "cpu") {
            let count = cpuLoadPerCore.count
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<count, id: \.self) { index in
                    let load = cpuLoadPerCore[index]
                    VStack(spacing: 4) {
                        Gauge(value: load) {
                            Text("")
                        } currentValueLabel: {
                            Text("\(Int(load * 100))")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .scaleEffect(0.7)
                        .frame(height: 30)
                        .tint(load > 0.9 ? .red : (load > 0.7 ? .orange : .green))
                        
                        Text("Core \(index)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct GPUDashboard: View {
    let gpuLoad: Double
    
    var body: some View {
        DashboardSection(title: "GPU Load", icon: "cpu.fill") {
            HStack {
                Gauge(value: gpuLoad) {
                    Text("GPU")
                } currentValueLabel: {
                    Text("\(Int(gpuLoad * 100))%")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(LinearGradient(gradient: Gradient(colors: [.purple, .pink]), startPoint: .leading, endPoint: .trailing))
            }
        }
    }
}

struct MemoryDashboard: View {
    let memoryUsed: Double
    let memoryTotal: Double
    let memoryPressure: Double
    let memorySwap: Double
    let showAdvancedMemory: Bool
    
    var body: some View {
        DashboardSection(title: "Memory", icon: "memorychip") {
            VStack(alignment: .leading, spacing: 6) {
                Gauge(value: memoryUsed, in: 0...memoryTotal) {
                    Text("Memory")
                } currentValueLabel: {
                    Text(String(format: "%.1f GB / %.1f GB", memoryUsed / 1_000_000_000, memoryTotal / 1_000_000_000))
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(LinearGradient(gradient: Gradient(colors: [.blue, .teal]), startPoint: .leading, endPoint: .trailing))
                
                if showAdvancedMemory {
                    HStack(spacing: 20) {
                        StatView(label: "Pressure", value: String(format: "%.0f%%", memoryPressure), color: memoryPressure > 80 ? .red : (memoryPressure > 50 ? .orange : .green))
                        StatView(label: "Swap", value: FormatUtils.formatBytes(memorySwap), color: .secondary)
                    }
                }
            }
        }
    }
}

struct BatteryDashboard: View {
    let batteryLevel: Double
    let batteryIsCharging: Bool
    let batteryPowerUsage: Double
    let batteryAdapterWattage: Int
    let batteryCycleCount: Int
    let batteryHealth: Double
    
    var body: some View {
        DashboardSection(title: "Battery", icon: "battery.100") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Gauge(value: batteryLevel) {
                        Text("Battery")
                    } currentValueLabel: {
                        Text("\(Int(batteryLevel * 100))%")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(batteryLevel < 0.2 ? .red : .green)
                    .scaleEffect(0.8)
                    .frame(width: 40, height: 40)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(batteryIsCharging ? "Charging" : "Discharging")
                            .font(.system(size: 11, weight: .bold))
                        if batteryPowerUsage != 0 {
                            Text(String(format: "%@: %.1f W", batteryPowerUsage > 0 ? "Rate" : "Power", abs(batteryPowerUsage)))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        if batteryAdapterWattage > 0 {
                            Text("Adapter: \(batteryAdapterWattage)W")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "Health: %.0f%%", batteryHealth * 100))
                        Text("Cycles: \(batteryCycleCount)")
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct SystemInfoDashboard: View {
    let diskFree: Int64
    let diskTotal: Int64
    let uptime: TimeInterval
    
    var body: some View {
        DashboardSection(title: "System Info", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 6) {
                if diskTotal > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        let used = diskTotal - diskFree
                        Gauge(value: Double(used), in: 0...Double(diskTotal)) {
                            Text("Disk")
                        } currentValueLabel: {
                            Text(String(format: "Free: %@", FormatUtils.formatBytes(Double(diskFree))))
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(LinearGradient(gradient: Gradient(colors: [.gray, .secondary]), startPoint: .leading, endPoint: .trailing))
                        
                        Text(String(format: "Total: %@", FormatUtils.formatBytes(Double(diskTotal))))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("Uptime: \(formatUptime(uptime))")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatUptime(_ uptime: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: uptime) ?? ""
    }
}

struct DiskDashboard: View {
    let diskReadRate: Double
    let diskWriteRate: Double
    
    var body: some View {
        DashboardSection(title: "Disk I/O", icon: "externaldrive") {
            VStack(alignment: .leading, spacing: 6) {
                StatView(label: "Read", value: FormatUtils.formatBytes(diskReadRate) + "/s", color: .green)
                StatView(label: "Write", value: FormatUtils.formatBytes(diskWriteRate) + "/s", color: .orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NetworkDashboard: View {
    let networkDownloadRate: Double
    let networkUploadRate: Double
    
    var body: some View {
        DashboardSection(title: "Network", icon: "network") {
            VStack(alignment: .leading, spacing: 6) {
                StatView(label: "Down", value: FormatUtils.formatBytes(networkDownloadRate) + "/s", icon: "arrow.down", color: .blue)
                StatView(label: "Up", value: FormatUtils.formatBytes(networkUploadRate) + "/s", icon: "arrow.up", color: .red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TopCPUDashboard: View {
    let topCPU: [TopProcess]
    
    var body: some View {
        DashboardSection(title: "Top CPU", icon: "list.bullet.rectangle") {
            VStack(spacing: 6) {
                ForEach(topCPU) { process in
                    ProcessRow(name: process.name, value: process.value)
                }
            }
        }
    }
}

struct TopMemoryDashboard: View {
    let topMemory: [TopProcess]
    
    var body: some View {
        DashboardSection(title: "Top Memory", icon: "list.bullet.indent") {
            VStack(spacing: 6) {
                ForEach(topMemory) { process in
                    ProcessRow(name: process.name, value: process.value)
                }
            }
        }
    }
}

// MARK: - UI Helpers

struct DashboardSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
            }
            content
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct StatView: View {
    let label: String
    let value: String
    var icon: String? = nil
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 8))
                }
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

struct ProcessRow: View {
    let name: String
    let value: String
    
    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Dynamic MenuBar Text", isOn: $monitor.showMenuBarText)
                            .fontWeight(.medium)
                        
                        Picker("Display Stat:", selection: $monitor.showMenuBarMode) {
                            ForEach(MenuBarDisplayMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .disabled(!monitor.showMenuBarText)
                    }
                    .padding(4)
                } label: {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("CPU Load", isOn: $monitor.showCPU)
                        Toggle("GPU Load", isOn: $monitor.showGPU)
                        Toggle("Memory Usage", isOn: $monitor.showMemory)
                        Toggle("Advanced Memory", isOn: $monitor.showAdvancedMemory)
                        Toggle("Battery Status", isOn: $monitor.showBattery)
                        Toggle("Disk I/O", isOn: $monitor.showDisk)
                        Toggle("Network Speed", isOn: $monitor.showNetwork)
                        Toggle("System Info", isOn: $monitor.showSystemInfo)
                        Toggle("Top CPU Processes", isOn: $monitor.showTopCPU)
                        Toggle("Top Memory Processes", isOn: $monitor.showTopMemory)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                } label: {
                    Label("Visibility", systemImage: "eye")
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Refresh every")
                            Text("\(Int(monitor.updateInterval))s")
                                .bold()
                                .foregroundColor(.accentColor)
                        }
                        Slider(value: $monitor.updateInterval, in: 1...10, step: 1.0)
                    }
                    .padding(4)
                } label: {
                    Label("Updates", systemImage: "timer")
                }
            }
            .padding()
        }
        .onChange(of: monitor.updateInterval) { _ in
            monitor.startMonitoring()
        }
    }
}
