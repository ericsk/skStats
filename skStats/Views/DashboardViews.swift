import SwiftUI
import Combine
import IOKit
import ServiceManagement

struct DashboardComponents {
    struct CPUDashboard: View {
        let cpuLoadPerCore: [Double]
        let totalLoad: Double
        let userLoad: Double
        let systemLoad: Double
        
        private func loadColor(_ value: Double) -> Color {
            if value > 0.9 { return .red }
            if value >= 0.7 { return .orange }
            return .green
        }
        
        var body: some View {
            DashboardSection(title: "CPU", icon: "cpu") {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            HStack(spacing: 6) {
                                Text("Total Load")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text("User \(FormatUtils.formatPercentage(userLoad)) · Sys \(FormatUtils.formatPercentage(systemLoad))")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            Spacer()
                            Text(FormatUtils.formatPercentage(totalLoad))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        
                        Gauge(value: totalLoad) {
                            Text("")
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(loadColor(totalLoad))
                        .frame(height: 8)
                        .animation(.easeInOut(duration: 0.6), value: totalLoad)
                    }
                    
                    if !cpuLoadPerCore.isEmpty {
                        Divider()
                            .opacity(0.3)
                        
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(0..<cpuLoadPerCore.count, id: \.self) { index in
                                let load = cpuLoadPerCore[index]
                                VStack(spacing: 4) {
                                    ZStack {
                                        Gauge(value: load) {
                                            Text("")
                                        }
                                        .gaugeStyle(.accessoryCircularCapacity)
                                        .tint(loadColor(load))
                                        .scaleEffect(0.8)
                                        .frame(width: 32, height: 32)
                                        .animation(.easeInOut(duration: 0.6), value: load)
                                        
                                        Text(String(format: "%.0f", load * 100))
                                            .font(.system(size: 8, weight: .bold, design: .rounded))
                                            .monospacedDigit()
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
    }

    struct GPUDashboard: View {
        let gpuLoad: Double
        let topGPU: [TopProcess]
        let showTopGPU: Bool
        
        var body: some View {
            DashboardSection(title: "GPU", icon: "square.grid.3x3.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Current Load")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(FormatUtils.formatPercentage(gpuLoad))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        
                        Gauge(value: gpuLoad) {
                            Text("")
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(LinearGradient(colors: [.purple, .indigo, .blue], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                        .animation(.easeInOut(duration: 0.6), value: gpuLoad)
                    }
                    
                    if showTopGPU && !topGPU.isEmpty {
                        Divider()
                            .padding(.vertical, 2)
                        
                        VStack(spacing: 8) {
                            let maxGPU = topGPU.first?.sortValue ?? 100.0
                            ForEach(topGPU) { process in
                                ProcessRow(name: process.name, value: process.value, load: process.sortValue / max(maxGPU, 1.0), color: .purple)
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: topGPU)
                    }
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
                            Text(String(format: "%.1f", memoryUsed / 1_073_741_824.0))
                            Text("/")
                            Text(FormatUtils.formatMemoryGB(memoryTotal))
                        }
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    }
                    
                    Gauge(value: memoryUsed, in: 0...max(memoryTotal, 1)) {
                        Text("")
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
                    .animation(.easeInOut(duration: 0.6), value: memoryUsed)
                    
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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Gauge(value: batteryLevel) {
                                Text("")
                            }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .tint(batteryLevel < 0.2 ? .red : .green)
                            .frame(width: 40, height: 40)
                            .animation(.easeInOut(duration: 0.8), value: batteryLevel)
                            
                            Image(systemName: batteryIsCharging ? "bolt.fill" : "battery.100")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(batteryIsCharging ? .yellow : .primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(FormatUtils.formatPercentage(batteryLevel))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text(batteryIsCharging ? "Charging (\(batteryAdapterWattage)W)" : "Discharging")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        if batteryPowerUsage != 0 {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: "%.1f W", abs(batteryPowerUsage)))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(batteryPowerUsage < 0 ? .green : .primary)
                                Text(batteryPowerUsage < 0 ? "Flow In" : "Flow Out")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Divider()
                        .opacity(0.3)
                    
                    HStack(spacing: 20) {
                        StatView(label: "Health", value: "\(Int(batteryHealth * 100))%", color: batteryHealth > 0.8 ? .green : (batteryHealth > 0.6 ? .orange : .red))
                        StatView(label: "Cycles", value: "\(batteryCycleCount)", color: .secondary)
                        if batteryTemperature > 0 {
                            StatView(label: "Temp", value: String(format: "%.1f°C", batteryTemperature), color: batteryTemperature > 45 ? .red : (batteryTemperature > 35 ? .orange : .secondary))
                        }
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
                        let used = max(diskTotal - diskFree, 0)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Disk Space")
                                    .font(.system(size: 10, weight: .semibold))
                                Spacer()
                                Text("\(FormatUtils.formatBytes(Double(diskFree))) free / \(FormatUtils.formatBytes(Double(diskTotal)))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: Double(used), total: Double(diskTotal))
                                .progressViewStyle(.linear)
                                .tint(Color.primary.opacity(0.6))
                                .animation(.easeInOut(duration: 0.6), value: used)
                        }
                    }
                    
                    HStack {
                        Label("Uptime", systemImage: "clock")
                            .font(.system(size: 10, weight: .semibold))
                        Spacer()
                        Text(FormatUtils.formatUptime(uptime))
                            .font(.system(size: 10, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            }
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
                .animation(.easeInOut(duration: 0.3), value: topCPU)
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
                .animation(.easeInOut(duration: 0.3), value: topMemory)
            }
        }
    }
}

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
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                .monospacedDigit()
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
                                .frame(width: geo.size.width * CGFloat(min(max(load, 0.0), 1.0)))
                                .animation(.easeInOut(duration: 0.4), value: load)
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
