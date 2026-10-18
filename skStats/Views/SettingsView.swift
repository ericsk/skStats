import SwiftUI

struct SettingsView: View {
    private static let twoColumns = [GridItem(.flexible()), GridItem(.flexible())]
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                SettingsGroup(title: "Menu Bar Display", icon: "menubar.rectangle") {
                    Toggle("Show Real-time Info Text", isOn: $monitor.showMenuBarText)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Metrics on Menu Bar:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: Self.twoColumns, alignment: .leading, spacing: 10) {
                            Toggle("CPU", isOn: $monitor.showMenuBarCPU)
                            Toggle("GPU", isOn: $monitor.showMenuBarGPU)
                            Toggle("Memory", isOn: $monitor.showMenuBarMemory)
                            Toggle("Network", isOn: $monitor.showMenuBarNetwork)
                            Toggle("Disk", isOn: $monitor.showMenuBarDisk)
                            if monitor.hasBattery {
                                Toggle("Battery", isOn: $monitor.showMenuBarBattery)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    .padding(.top, 4)
                }
                
                SettingsGroup(title: "General", icon: "gearshape.fill") {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { monitor.launchAtLogin },
                        set: { monitor.setLaunchAtLogin($0) }
                    ))
                }
                
                SettingsGroup(title: "Visibility", icon: "eye.fill") {
                    LazyVGrid(columns: Self.twoColumns, alignment: .leading, spacing: 12) {
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
                        Toggle("Top GPU", isOn: $monitor.showTopGPU)
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
