import SwiftUI

private struct DashboardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var isShowingSettings = false
    @State private var dashboardHeight: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            if isShowingSettings {
                settingsHeader
                SettingsView(monitor: monitor)
                    .frame(maxHeight: 520)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            } else {
                mainHeader
                Group {
                    if let stats = monitor.currentStats {
                        ScrollView(showsIndicators: false) {
                            DashboardBodyView(
                                stats: stats,
                                isVisible: monitor.isPopoverVisible,
                                memoryTotal: monitor.memoryTotal,
                                hasBattery: monitor.hasBattery,
                                showCPU: monitor.showCPU,
                                showGPU: monitor.showGPU,
                                showMemory: monitor.showMemory,
                                showBattery: monitor.showBattery,
                                showDisk: monitor.showDisk,
                                showNetwork: monitor.showNetwork,
                                showSystemInfo: monitor.showSystemInfo,
                                showTopCPU: monitor.showTopCPU,
                                showTopGPU: monitor.showTopGPU,
                                showTopMemory: monitor.showTopMemory,
                                showAdvancedMemory: monitor.showAdvancedMemory
                            )
                            .equatable()
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(key: DashboardHeightPreferenceKey.self, value: geo.size.height)
                                }
                            )
                        }
                        .onPreferenceChange(DashboardHeightPreferenceKey.self) { height in
                            if abs(dashboardHeight - height) > 0.5 {
                                dashboardHeight = height
                            }
                        }
                        .frame(height: dashboardHeight > 0 ? min(dashboardHeight, 740) : nil)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        loadingPlaceholder
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
            }
        }
        .frame(width: 340)
        .fixedSize(horizontal: true, vertical: dashboardHeight == 0 || isShowingSettings)
        .background {
            VisualEffectView(
                material: .popover,
                blendingMode: .behindWindow,
                onVisibilityChange: { visible in
                    if monitor.isPopoverVisible != visible {
                        monitor.isPopoverVisible = visible
                    }
                }
            )
            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isShowingSettings)
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
                        .equatable()
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
            Button {
                isShowingSettings = false
                monitor.updateStats()
            } label: {
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

private struct DashboardBodyView: View, Equatable {
    let stats: SystemStats
    let isVisible: Bool
    let memoryTotal: Double
    let hasBattery: Bool
    let showCPU: Bool
    let showGPU: Bool
    let showMemory: Bool
    let showBattery: Bool
    let showDisk: Bool
    let showNetwork: Bool
    let showSystemInfo: Bool
    let showTopCPU: Bool
    let showTopGPU: Bool
    let showTopMemory: Bool
    let showAdvancedMemory: Bool
    
    static func == (lhs: DashboardBodyView, rhs: DashboardBodyView) -> Bool {
        // When the popover window is hidden, skip all dashboard body evaluations during background Menu Bar updates.
        if !lhs.isVisible && !rhs.isVisible {
            return true
        }
        return lhs.isVisible == rhs.isVisible &&
               lhs.stats == rhs.stats &&
               lhs.memoryTotal == rhs.memoryTotal &&
               lhs.hasBattery == rhs.hasBattery &&
               lhs.showCPU == rhs.showCPU &&
               lhs.showGPU == rhs.showGPU &&
               lhs.showMemory == rhs.showMemory &&
               lhs.showBattery == rhs.showBattery &&
               lhs.showDisk == rhs.showDisk &&
               lhs.showNetwork == rhs.showNetwork &&
               lhs.showSystemInfo == rhs.showSystemInfo &&
               lhs.showTopCPU == rhs.showTopCPU &&
               lhs.showTopGPU == rhs.showTopGPU &&
               lhs.showTopMemory == rhs.showTopMemory &&
               lhs.showAdvancedMemory == rhs.showAdvancedMemory
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showCPU {
                DashboardComponents.CPUDashboard(
                    cpuLoadPerCore: stats.cpuLoadPerCore,
                    totalLoad: stats.totalCPULoad,
                    userLoad: stats.cpuUserLoad,
                    systemLoad: stats.cpuSystemLoad
                )
                .equatable()
            }
            if showGPU {
                DashboardComponents.GPUDashboard(
                    gpuLoad: stats.gpuLoad,
                    topGPU: stats.topGPU,
                    showTopGPU: showTopGPU
                )
                .equatable()
            }
            if showMemory {
                DashboardComponents.MemoryDashboard(
                    memoryUsed: stats.memoryUsed,
                    memoryTotal: memoryTotal,
                    memoryPressure: stats.memoryPressure,
                    memorySwap: stats.memorySwap,
                    showAdvancedMemory: showAdvancedMemory
                )
                .equatable()
            }
            if hasBattery && showBattery {
                DashboardComponents.BatteryDashboard(
                    batteryLevel: stats.batteryLevel,
                    batteryIsCharging: stats.batteryIsCharging,
                    batteryPowerUsage: stats.batteryPowerUsage,
                    batteryAdapterWattage: stats.batteryAdapterWattage,
                    batteryCycleCount: stats.batteryCycleCount,
                    batteryHealth: stats.batteryHealth,
                    batteryTemperature: stats.batteryTemperature
                )
                .equatable()
            }
            if showDisk || showNetwork {
                HStack(alignment: .top, spacing: 6) {
                    if showDisk {
                        DashboardComponents.DiskDashboard(diskReadRate: stats.diskRead, diskWriteRate: stats.diskWrite)
                            .equatable()
                            .frame(maxWidth: .infinity)
                    }
                    if showNetwork {
                        DashboardComponents.NetworkDashboard(networkDownloadRate: stats.netDown, networkUploadRate: stats.netUp)
                            .equatable()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            if showSystemInfo {
                DashboardComponents.SystemInfoDashboard(diskFree: stats.diskFree, diskTotal: stats.diskTotal, uptime: stats.uptime)
                    .equatable()
            }
            if showTopCPU && !stats.topCPU.isEmpty {
                DashboardComponents.TopCPUDashboard(topCPU: stats.topCPU)
                    .equatable()
            }
            if showTopMemory && !stats.topMemory.isEmpty {
                DashboardComponents.TopMemoryDashboard(topMemory: stats.topMemory)
                    .equatable()
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}

