import Foundation
import Combine
import SwiftUI
import Darwin
import IOKit
import ServiceManagement

@MainActor
class SystemMonitor: ObservableObject {
    @Published var currentStats: SystemStats? = nil
    @Published var isPopoverVisible: Bool = false {
        didSet {
            if isPopoverVisible && !oldValue {
                updateStats()
            }
        }
    }
    @Published var memoryTotal: Double = 0.0
    @Published var hasBattery: Bool = false
    @Published var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    
    @AppStorage("showCPU") var showCPU: Bool = true
    @AppStorage("showGPU") var showGPU: Bool = true
    @AppStorage("showMemory") var showMemory: Bool = true
    @AppStorage("showDisk") var showDisk: Bool = true
    @AppStorage("showNetwork") var showNetwork: Bool = true
    @AppStorage("showTopCPU") var showTopCPU: Bool = true
    @AppStorage("showTopMemory") var showTopMemory: Bool = true
    @AppStorage("showTopGPU") var showTopGPU: Bool = true
    @AppStorage("showBattery") var showBattery: Bool = true
    @AppStorage("showAdvancedMemory") var showAdvancedMemory: Bool = true
    @AppStorage("showSystemInfo") var showSystemInfo: Bool = true
    
    @AppStorage("showMenuBarMode") var showMenuBarMode: MenuBarDisplayMode = .cpu
    @AppStorage("showMenuBarText") var showMenuBarText: Bool = true
    @AppStorage("updateInterval") var updateInterval: Double = 3.0
    
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    
    private var timer: AnyCancellable?
    private var debounceTask: Task<Void, Never>?
    private let worker = TelemetryWorker()
    private var thermalObserver: AnyCancellable?
    
    init() {
        self.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        self.hasBattery = checkBatteryPresence()
        
        // Observe thermal state changes instantly
        self.thermalObserver = NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.thermalState = ProcessInfo.processInfo.thermalState
            }
            
        startMonitoring()
    }
    
    private func checkBatteryPresence() -> Bool {
        let matchingDict = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == kIOReturnSuccess {
            let service = IOIteratorNext(iterator)
            if service != 0 {
                IOObjectRelease(service)
                IOObjectRelease(iterator)
                return true
            }
            IOObjectRelease(iterator)
        }
        return false
    }
    
    func startMonitoring() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                timer?.cancel()
                updateStats()
                timer = Timer.publish(every: updateInterval, on: .main, in: .common)
                    .autoconnect()
                    .sink { [weak self] _ in
                        self?.updateStats()
                    }
            }
        }
    }
    
    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login status: \(error)")
            // Rollback on failure
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
    
    private var isUpdating = false
    
    func updateStats() {
        guard !isUpdating else { return }
        isUpdating = true
        
        let interval = updateInterval
        let isVisible = isPopoverVisible
        let options = TelemetryWorker.FetchOptions(
            cpu: isVisible ? showCPU : (showMenuBarMode == .cpu),
            gpu: isVisible ? showGPU : (showMenuBarMode == .gpu),
            memory: isVisible ? showMemory : (showMenuBarMode == .memory),
            disk: isVisible ? showDisk : (showMenuBarMode == .disk),
            network: isVisible ? showNetwork : (showMenuBarMode == .network),
            battery: isVisible ? showBattery : (showMenuBarMode == .battery),
            advancedMemory: isVisible ? showAdvancedMemory : false,
            systemInfo: isVisible ? showSystemInfo : false,
            topCPU: isVisible ? showTopCPU : false,
            topGPU: isVisible ? showTopGPU : false,
            topMemory: isVisible ? showTopMemory : false
        )
        let totalMem = memoryTotal
        
        Task {
            let stats = await worker.fetchStats(interval: interval, options: options, totalMemory: totalMem)
            self.currentStats = stats
            self.isUpdating = false
        }
    }
}
