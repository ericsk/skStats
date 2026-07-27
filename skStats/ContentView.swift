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
                            if monitor.showCPU { DashboardComponents.CPUDashboard(cpuLoadPerCore: stats.cpuLoadPerCore) }
                            if monitor.showGPU { DashboardComponents.GPUDashboard(gpuLoad: stats.gpuLoad, topGPU: stats.topGPU, showTopGPU: monitor.showTopGPU) }
                            if monitor.showMemory { 
                                DashboardComponents.MemoryDashboard(
                                    memoryUsed: stats.memoryUsed, 
                                    memoryTotal: monitor.memoryTotal, 
                                    memoryPressure: stats.memoryPressure, 
                                    memorySwap: stats.memorySwap, 
                                    showAdvancedMemory: monitor.showAdvancedMemory
                                ) 
                            }
                            if monitor.hasBattery && monitor.showBattery { 
                                DashboardComponents.BatteryDashboard(
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
                                        DashboardComponents.DiskDashboard(diskReadRate: stats.diskRead, diskWriteRate: stats.diskWrite)
                                            .frame(maxWidth: .infinity)
                                    }
                                    if monitor.showNetwork {
                                        DashboardComponents.NetworkDashboard(networkDownloadRate: stats.netDown, networkUploadRate: stats.netUp)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            if monitor.showSystemInfo { 
                                DashboardComponents.SystemInfoDashboard(diskFree: stats.diskFree, diskTotal: stats.diskTotal, uptime: stats.uptime) 
                            }
                            if monitor.showTopCPU && !stats.topCPU.isEmpty { DashboardComponents.TopCPUDashboard(topCPU: stats.topCPU) }
                            if monitor.showTopMemory && !stats.topMemory.isEmpty { DashboardComponents.TopMemoryDashboard(topMemory: stats.topMemory) }
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
