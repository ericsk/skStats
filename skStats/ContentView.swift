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
                VStack(alignment: .leading, spacing: 14) {
                    if monitor.showCPU { CPUDashboard(monitor: monitor) }
                    if monitor.showGPU { GPUDashboard(monitor: monitor) }
                    if monitor.showMemory { MemoryDashboard(monitor: monitor) }
                    if monitor.showDisk { DiskDashboard(monitor: monitor) }
                    if monitor.showNetwork { NetworkDashboard(monitor: monitor) }
                    if monitor.showTopCPU && !monitor.topCPU.isEmpty { TopCPUDashboard(monitor: monitor) }
                    if monitor.showTopMemory && !monitor.topMemory.isEmpty { TopMemoryDashboard(monitor: monitor) }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                .transition(.move(edge: .leading))
            }
        }
        .frame(width: 320)
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isShowingSettings)
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
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        DashboardSection(title: "CPU Load", icon: "cpu") {
            let count = monitor.cpuLoadPerCore.count
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<count, id: \.self) { index in
                    let load = monitor.cpuLoadPerCore[index]
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
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        DashboardSection(title: "GPU Load", icon: "cpu.fill") {
            HStack {
                Gauge(value: monitor.gpuLoad) {
                    Text("GPU")
                } currentValueLabel: {
                    Text("\(Int(monitor.gpuLoad * 100))%")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(.purple)
            }
        }
    }
}

struct MemoryDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        DashboardSection(title: "Memory", icon: "memorychip") {
            VStack(alignment: .leading, spacing: 4) {
                Gauge(value: monitor.memoryUsed, in: 0...monitor.memoryTotal) {
                    Text("Memory")
                } currentValueLabel: {
                    Text(String(format: "%.1f GB / %.1f GB", monitor.memoryUsed / 1_000_000_000, monitor.memoryTotal / 1_000_000_000))
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(.blue)
                
                Text(String(format: "Usage: %.0f%%", (monitor.memoryUsed / monitor.memoryTotal) * 100))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct DiskDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        DashboardSection(title: "Disk I/O", icon: "externaldrive") {
            HStack(spacing: 20) {
                StatView(label: "Read", value: FormatUtils.formatBytes(monitor.diskReadRate) + "/s", color: .green)
                StatView(label: "Write", value: FormatUtils.formatBytes(monitor.diskWriteRate) + "/s", color: .orange)
            }
        }
    }
}

struct NetworkDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        DashboardSection(title: "Network", icon: "network") {
            HStack(spacing: 20) {
                StatView(label: "Down", value: FormatUtils.formatBytes(monitor.networkDownloadRate) + "/s", icon: "arrow.down", color: .blue)
                StatView(label: "Up", value: FormatUtils.formatBytes(monitor.networkUploadRate) + "/s", icon: "arrow.up", color: .red)
            }
        }
    }
}

struct TopCPUDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        DashboardSection(title: "Top CPU", icon: "list.bullet.rectangle") {
            VStack(spacing: 6) {
                ForEach(monitor.topCPU) { process in
                    ProcessRow(name: process.name, value: process.value)
                }
            }
        }
    }
}

struct TopMemoryDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        DashboardSection(title: "Top Memory", icon: "list.bullet.indent") {
            VStack(spacing: 6) {
                ForEach(monitor.topMemory) { process in
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
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
            }
            content
            Divider()
                .padding(.top, 4)
        }
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
                        Toggle("Disk I/O", isOn: $monitor.showDisk)
                        Toggle("Network Speed", isOn: $monitor.showNetwork)
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
