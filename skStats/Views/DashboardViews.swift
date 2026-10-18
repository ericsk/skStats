import SwiftUI
import AppKit

struct DashboardComponents {
    private static let coreGridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private static let gpuGradient = LinearGradient(colors: [.purple, .indigo, .blue], startPoint: .leading, endPoint: .trailing)
    private static let memoryGradient = LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)

    static func loadColor(_ value: Double) -> Color {
        if value > 0.9 { return .red }
        if value >= 0.7 { return .orange }
        return .green
    }

    struct CPUDashboard: View, Equatable {
        let cpuLoadPerCore: [Double]
        let totalLoad: Double
        let userLoad: Double
        let systemLoad: Double
        
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
                            EmptyView()
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(DashboardComponents.loadColor(totalLoad))
                        .frame(height: 8)
                    }
                    
                    if !cpuLoadPerCore.isEmpty {
                        Divider()
                            .opacity(0.3)
                        
                        LazyVGrid(columns: DashboardComponents.coreGridColumns, spacing: 14) {
                            ForEach(0..<cpuLoadPerCore.count, id: \.self) { index in
                                CoreGaugeCell(index: index, load: cpuLoadPerCore[index])
                                    .equatable()
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    private struct CoreGaugeCell: View, Equatable {
        let index: Int
        let load: Double
        
        var body: some View {
            let color = DashboardComponents.loadColor(load)
            let clamped = CGFloat(min(max(load, 0.0), 1.0))
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.2), lineWidth: 3)
                        .frame(width: 26, height: 26)
                    
                    Circle()
                        .trim(from: 0, to: clamped)
                        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 26, height: 26)
                    
                    Text(String(format: "%.0f", load * 100))
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 32, height: 32)
                
                Text("Core \(index)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    struct GPUDashboard: View, Equatable {
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
                            EmptyView()
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(DashboardComponents.gpuGradient)
                        .frame(height: 8)
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
                    }
                }
            }
        }
    }

    struct MemoryDashboard: View, Equatable {
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
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(DashboardComponents.memoryGradient)
                    .frame(height: 8)
                    
                    if showAdvancedMemory {
                        HStack(spacing: 24) {
                            StatView(label: "Pressure", value: String(format: "%.0f%%", memoryPressure), color: memoryPressure > 75 ? .red : (memoryPressure > 50 ? .orange : .green))
                                .equatable()
                            StatView(label: "Swap", value: FormatUtils.formatBytes(memorySwap), color: .secondary)
                                .equatable()
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    struct BatteryDashboard: View, Equatable {
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
                                EmptyView()
                            }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .tint(batteryLevel < 0.2 ? .red : .green)
                            .frame(width: 40, height: 40)
                            
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
                            let isFlowingIn = batteryIsCharging || batteryPowerUsage > 0
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: "%.1f W", abs(batteryPowerUsage)))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(isFlowingIn ? .green : .primary)
                                Text(isFlowingIn ? "Flow In" : "Flow Out")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Divider()
                        .opacity(0.3)
                    
                    HStack(spacing: 20) {
                        StatView(label: "Health", value: "\(Int(batteryHealth * 100))%", color: batteryHealth > 0.8 ? .green : (batteryHealth > 0.6 ? .orange : .red))
                            .equatable()
                        StatView(label: "Cycles", value: "\(batteryCycleCount)", color: .secondary)
                            .equatable()
                        if batteryTemperature > 0 {
                            StatView(label: "Temp", value: String(format: "%.1f°C", batteryTemperature), color: batteryTemperature > 45 ? .red : (batteryTemperature > 35 ? .orange : .secondary))
                                .equatable()
                        }
                    }
                }
            }
        }
    }

    struct DiskDashboard: View, Equatable {
        let diskReadRate: Double
        let diskWriteRate: Double
        
        var body: some View {
            DashboardSection(title: "Disk", icon: "internaldrive") {
                VStack(alignment: .leading, spacing: 8) {
                    StatView(label: "Read", value: FormatUtils.formatRate(diskReadRate), icon: "arrow.down.circle", color: .green)
                        .equatable()
                    StatView(label: "Write", value: FormatUtils.formatRate(diskWriteRate), icon: "arrow.up.circle", color: .orange)
                        .equatable()
                }
            }
        }
    }

    struct NetworkDashboard: View, Equatable {
        let networkDownloadRate: Double
        let networkUploadRate: Double
        
        var body: some View {
            DashboardSection(title: "Network", icon: "wifi") {
                VStack(alignment: .leading, spacing: 8) {
                    StatView(label: "Down", value: FormatUtils.formatRate(networkDownloadRate), icon: "arrow.down.square", color: .blue)
                        .equatable()
                    StatView(label: "Up", value: FormatUtils.formatRate(networkUploadRate), icon: "arrow.up.square", color: .rose)
                        .equatable()
                }
            }
        }
    }

    struct SystemInfoDashboard: View, Equatable {
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

    struct TopCPUDashboard: View, Equatable {
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

    struct TopMemoryDashboard: View, Equatable {
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

struct StatView: View, Equatable {
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
        let clampedLoad = CGFloat(min(max(load, 0.0), 1.0))
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
                .background {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(color.opacity(isHovered ? 0.15 : 0.1))
                        
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(color.opacity(isHovered ? 0.3 : 0.2))
                            .scaleEffect(x: clampedLoad, y: 1.0, anchor: .leading)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
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

final class PopoverVisualEffectView: NSVisualEffectView {
    var onVisibilityChange: ((Bool) -> Void)?
    private var windowObservers: [NSObjectProtocol] = []
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowObservers()
        guard let window = self.window else {
            onVisibilityChange?(false)
            return
        }
        let nc = NotificationCenter.default
        let updateVisibility: (Notification) -> Void = { [weak self, weak window] _ in
            guard let self = self, let window = window else { return }
            let visible = window.isVisible && window.occlusionState.contains(.visible)
            self.onVisibilityChange?(visible)
        }
        windowObservers.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main, using: updateVisibility))
        windowObservers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main, using: updateVisibility))
        windowObservers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self, weak window] _ in
            guard let self = self, let window = window else { return }
            let visible = window.isVisible && window.occlusionState.contains(.visible)
            self.onVisibilityChange?(visible)
        })
        let initiallyVisible = window.isVisible && window.occlusionState.contains(.visible)
        onVisibilityChange?(initiallyVisible)
    }
    
    private func removeWindowObservers() {
        let nc = NotificationCenter.default
        for observer in windowObservers {
            nc.removeObserver(observer)
        }
        windowObservers.removeAll()
    }
    
    deinit {
        removeWindowObservers()
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var onVisibilityChange: ((Bool) -> Void)? = nil
    
    func makeNSView(context: Context) -> PopoverVisualEffectView {
        let view = PopoverVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        view.onVisibilityChange = onVisibilityChange
        return view
    }
    
    func updateNSView(_ nsView: PopoverVisualEffectView, context: Context) {
        nsView.onVisibilityChange = onVisibilityChange
    }
}

struct ThermalStateBadge: View, Equatable {
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

