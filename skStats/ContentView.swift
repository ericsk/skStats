import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var isShowingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isShowingSettings {
                settingsHeader
                SettingsView(monitor: monitor)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            } else {
                mainHeader
                VStack(alignment: .leading, spacing: 10) {
                    if let stats = monitor.currentStats {
                        Group {
                            if monitor.showCPU { CPUDashboard(cpuLoadPerCore: stats.cpuLoadPerCore) }
                            if monitor.showGPU { GPUDashboard(gpuLoad: stats.gpuLoad) }
                            if monitor.showMemory { 
                                MemoryDashboard(
                                    memoryUsed: stats.memoryUsed, 
                                    memoryTotal: monitor.memoryTotal, 
                                    memoryPressure: stats.memoryPressure, 
                                    memorySwap: stats.memorySwap, 
                                    showAdvancedMemory: monitor.showAdvancedMemory
                                ) 
                            }
                            if monitor.hasBattery && monitor.showBattery { 
                                BatteryDashboard(
                                    batteryLevel: stats.batteryLevel, 
                                    batteryIsCharging: stats.batteryIsCharging, 
                                    batteryPowerUsage: stats.batteryPowerUsage, 
                                    batteryAdapterWattage: stats.batteryAdapterWattage, 
                                    batteryCycleCount: stats.batteryCycleCount, 
                                    batteryHealth: stats.batteryHealth,
                                    batteryTemperature: stats.batteryTemperature
                                ) 
                            }
                            if monitor.showDisk || monitor.showNetwork {
                                HStack(alignment: .top, spacing: 6) {
                                    if monitor.showDisk {
                                        DiskDashboard(diskReadRate: stats.diskRead, diskWriteRate: stats.diskWrite)
                                            .frame(maxWidth: .infinity)
                                    }
                                    if monitor.showNetwork {
                                        NetworkDashboard(networkDownloadRate: stats.netDown, networkUploadRate: stats.netUp)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            if monitor.showSystemInfo { 
                                SystemInfoDashboard(diskFree: stats.diskFree, diskTotal: stats.diskTotal, uptime: stats.uptime) 
                            }
                            if monitor.showTopCPU && !stats.topCPU.isEmpty { TopCPUDashboard(topCPU: stats.topCPU) }
                            if monitor.showTopMemory && !stats.topMemory.isEmpty { TopMemoryDashboard(topMemory: stats.topMemory) }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        loadingPlaceholder
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
            }
        }
        .frame(width: 340)
        .frame(minHeight: 400, maxHeight: 1200)
        .fixedSize(horizontal: true, vertical: true)
        .background {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isShowingSettings)
        .animation(.easeInOut(duration: 0.5), value: monitor.currentStats)
        .onAppear { monitor.isPopoverVisible = true }
        .onDisappear { monitor.isPopoverVisible = false }
    }
    
    private var mainHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("skStats")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.accentColor, .blue], startPoint: .leading, endPoint: .trailing))
                HStack(spacing: 6) {
                    Text("System Monitor")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    ThermalStateBadge(state: monitor.thermalState)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                Button { isShowingSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
                
                Button { 
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Activity Monitor")
                
                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Quit skStats")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    private var settingsHeader: some View {
        HStack {
            Button { isShowingSettings = false } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Settings")
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    private var loadingPlaceholder: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Gathering telemetry...")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

// MARK: - Components

struct DashboardSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    @State private var isHovered = false
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundColor(.secondary.opacity(0.8))
                    .kerning(0.5)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(isHovered ? 0.45 : 0.3))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(LinearGradient(colors: [isHovered ? .accentColor.opacity(0.4) : .white.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .shadow(color: isHovered ? .accentColor.opacity(0.15) : .black.opacity(0.08), radius: isHovered ? 8 : 4, x: 0, y: isHovered ? 4 : 2)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

struct CPUDashboard: View {
    let cpuLoadPerCore: [Double]
    
    var body: some View {
        DashboardSection(title: "CPU", icon: "cpu") {
            VStack(spacing: 12) {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<cpuLoadPerCore.count, id: \.self) { index in
                        let load = cpuLoadPerCore[index]
                        VStack(spacing: 4) {
                            ZStack {
                                Gauge(value: load) {
                                    Text("")
                                }
                                .gaugeStyle(.accessoryCircularCapacity)
                                .tint(load > 0.8 ? .red : (load > 0.5 ? .orange : .accentColor))
                                .scaleEffect(0.8)
                                .frame(width: 32, height: 32)
                                
                                Text(String(format: "%.0f", load * 100))
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                            }
                            
                            Text("Core \(index)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

struct GPUDashboard: View {
    let gpuLoad: Double
    
    var body: some View {
        DashboardSection(title: "GPU", icon: "square.grid.3x3.fill") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Current Load")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(FormatUtils.formatPercentage(gpuLoad))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                
                Gauge(value: gpuLoad) {
                    Text("")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(LinearGradient(colors: [.purple, .indigo, .blue], startPoint: .leading, endPoint: .trailing))
                .frame(height: 8)
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
                HStack {
                    Text("Usage")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 2) {
                        Text(String(format: "%.1f", memoryUsed / 1_000_000_000))
                        Text("/")
                        Text(String(format: "%.0f GB", memoryTotal / 1_000_000_000))
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                
                Gauge(value: memoryUsed, in: 0...memoryTotal) {
                    Text("")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                .frame(height: 8)
                
                if showAdvancedMemory {
                    HStack(spacing: 24) {
                        StatView(label: "Pressure", value: String(format: "%.0f%%", memoryPressure), color: memoryPressure > 75 ? .red : (memoryPressure > 50 ? .orange : .green))
                        StatView(label: "Swap", value: FormatUtils.formatBytes(memorySwap), color: .secondary)
                    }
                    .padding(.top, 4)
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
    let batteryTemperature: Double
    
    var body: some View {
        DashboardSection(title: "Battery", icon: "bolt.fill") {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Gauge(value: batteryLevel) {
                        Text("")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(batteryLevel < 0.2 ? .red : .green)
                    .frame(width: 44, height: 44)
                    
                    Image(systemName: batteryIsCharging ? "bolt.fill" : "battery.100")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(batteryIsCharging ? .yellow : .primary)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(FormatUtils.formatPercentage(batteryLevel))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(batteryIsCharging ? "Charging (\(batteryAdapterWattage)W) • \(String(format: "%.1fW", abs(batteryPowerUsage)))" : "Discharging")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    if batteryPowerUsage != 0 {
                        Text(String(format: "%.1f W", abs(batteryPowerUsage)))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    HStack(spacing: 6) {
                        Text("Health: \(Int(batteryHealth * 100))%")
                        Text("•")
                        Text("Cycles: \(batteryCycleCount)")
                        if batteryTemperature > 0 {
                            Text("•")
                            Text(String(format: "%.1f°C", batteryTemperature))
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.8))
                }
            }
        }
    }
}

struct DiskDashboard: View {
    let diskReadRate: Double
    let diskWriteRate: Double
    
    var body: some View {
        DashboardSection(title: "Disk", icon: "internaldrive") {
            VStack(alignment: .leading, spacing: 8) {
                StatView(label: "Read", value: FormatUtils.formatRate(diskReadRate), icon: "arrow.down.circle", color: .green)
                StatView(label: "Write", value: FormatUtils.formatRate(diskWriteRate), icon: "arrow.up.circle", color: .orange)
            }
        }
    }
}

struct NetworkDashboard: View {
    let networkDownloadRate: Double
    let networkUploadRate: Double
    
    var body: some View {
        DashboardSection(title: "Network", icon: "wifi") {
            VStack(alignment: .leading, spacing: 8) {
                StatView(label: "Down", value: FormatUtils.formatRate(networkDownloadRate), icon: "arrow.down.square", color: .blue)
                StatView(label: "Up", value: FormatUtils.formatRate(networkUploadRate), icon: "arrow.up.square", color: .rose)
            }
        }
    }
}

struct SystemInfoDashboard: View {
    let diskFree: Int64
    let diskTotal: Int64
    let uptime: TimeInterval
    
    var body: some View {
        DashboardSection(title: "System Stats", icon: "info.circle.fill") {
            VStack(alignment: .leading, spacing: 10) {
                if diskTotal > 0 {
                    let used = diskTotal - diskFree
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Disk Space")
                                .font(.system(size: 10, weight: .semibold))
                            Spacer()
                            Text("\(FormatUtils.formatBytes(Double(diskFree))) free")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: Double(used), total: Double(diskTotal))
                            .progressViewStyle(.linear)
                            .tint(Color.primary.opacity(0.6))
                    }
                }
                
                HStack {
                    Label("Uptime", systemImage: "clock")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text(formatUptime(uptime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
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

struct TopCPUDashboard: View {
    let topCPU: [TopProcess]
    
    var body: some View {
        DashboardSection(title: "Active Processes", icon: "list.bullet.rectangle.stack") {
            VStack(spacing: 8) {
                let maxCPU = topCPU.first?.sortValue ?? 100.0
                ForEach(topCPU) { process in
                    ProcessRow(name: process.name, value: process.value, load: process.sortValue / max(maxCPU, 1.0), color: .accentColor)
                }
            }
        }
    }
}

struct TopMemoryDashboard: View {
    let topMemory: [TopProcess]
    
    var body: some View {
        DashboardSection(title: "Memory Hoggers", icon: "memorychip.fill") {
            VStack(spacing: 8) {
                let maxMem = topMemory.first?.sortValue ?? 1.0
                ForEach(topMemory) { process in
                    ProcessRow(name: process.name, value: process.value, load: process.sortValue / max(maxMem, 1.0), color: .cyan)
                }
            }
        }
    }
}

// MARK: - UI Helpers

struct StatView: View {
    let label: String
    let value: String
    var icon: String? = nil
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.8))
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }
        }
    }
}

struct ProcessRow: View {
    let name: String
    let value: String
    let load: Double
    let color: Color
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 11, weight: isHovered ? .semibold : .medium))
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(color.opacity(isHovered ? 0.15 : 0.1))
                            
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(color.opacity(isHovered ? 0.3 : 0.2))
                                .frame(width: geo.size.width * CGFloat(load))
                        }
                    }
                )
                .cornerRadius(6)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

extension Color {
    static let rose = Color(red: 255/255, green: 51/255, blue: 102/255)
}

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

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                SettingsGroup(title: "Menu Bar", icon: "menubar.rectangle") {
                    Toggle("Show Real-time Info", isOn: $monitor.showMenuBarText)
                    
                    if monitor.showMenuBarText {
                        Picker("Display Mode", selection: $monitor.showMenuBarMode) {
                            ForEach(MenuBarDisplayMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                SettingsGroup(title: "General", icon: "gearshape.fill") {
                    Toggle("Launch at Login", isOn: $monitor.launchAtLogin)
                        .onChange(of: monitor.launchAtLogin) { _ in
                            monitor.toggleLaunchAtLogin()
                        }
                }
                
                SettingsGroup(title: "Visibility", icon: "eye.fill") {
                    let columns = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        Toggle("CPU", isOn: $monitor.showCPU)
                        Toggle("GPU", isOn: $monitor.showGPU)
                        Toggle("RAM", isOn: $monitor.showMemory)
                        if monitor.hasBattery {
                            Toggle("Battery", isOn: $monitor.showBattery)
                        }
                        Toggle("Disk", isOn: $monitor.showDisk)
                        Toggle("Net", isOn: $monitor.showNetwork)
                        Toggle("Sys Info", isOn: $monitor.showSystemInfo)
                        Toggle("Top CPU", isOn: $monitor.showTopCPU)
                        Toggle("Top RAM", isOn: $monitor.showTopMemory)
                        Toggle("Adv RAM", isOn: $monitor.showAdvancedMemory)
                    }
                    .toggleStyle(.checkbox)
                }
                
                SettingsGroup(title: "Updates", icon: "timer") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Refresh Rate")
                            Spacer()
                            Text("\(Int(monitor.updateInterval))s")
                                .bold()
                                .foregroundColor(.accentColor)
                        }
                        Slider(value: $monitor.updateInterval, in: 1...10, step: 1.0)
                            .tint(.accentColor)
                    }
                }
            }
            .padding(20)
        }
        .onChange(of: monitor.updateInterval) { _ in
            monitor.startMonitoring()
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
        }
    }
}

struct ThermalStateBadge: View {
    let state: ProcessInfo.ThermalState
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.6), radius: 2)
            
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(color.opacity(0.1))
        .cornerRadius(6)
        .help("System Thermal State: \(fullDescription)")
    }
    
    private var color: Color {
        switch state {
        case .nominal: return .green
        case .fair: return .orange
        case .serious: return .red
        case .critical: return .red
        @unknown default: return .secondary
        }
    }
    
    private var label: String {
        switch state {
        case .nominal: return "COOL"
        case .fair: return "WARM"
        case .serious: return "THROTTLED"
        case .critical: return "HOT"
        @unknown default: return "UNKNOWN"
        }
    }
    
    private var fullDescription: String {
        switch state {
        case .nominal: return "Nominal (Cool & stable)"
        case .fair: return "Fair (Slightly elevated)"
        case .serious: return "Serious (System is throttling to cool down)"
        case .critical: return "Critical (Maximum cooling active, critical performance impact)"
        @unknown default: return "Unknown"
        }
    }
}
