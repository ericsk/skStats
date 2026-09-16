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
    
    @AppStorage("showMenuBarCPU") var showMenuBarCPU: Bool = true
    @AppStorage("showMenuBarGPU") var showMenuBarGPU: Bool = false
    @AppStorage("showMenuBarMemory") var showMenuBarMemory: Bool = false
    @AppStorage("showMenuBarNetwork") var showMenuBarNetwork: Bool = false
    @AppStorage("showMenuBarDisk") var showMenuBarDisk: Bool = false
    @AppStorage("showMenuBarBattery") var showMenuBarBattery: Bool = false
    
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
            
        startMonitoring(immediate: true)
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
    
    func startMonitoring(immediate: Bool = false) {
        debounceTask?.cancel()
        if immediate {
            setupTimer()
        } else {
            debounceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled, let self = self else { return }
                self.setupTimer()
            }
        }
    }
    
    private func setupTimer() {
        timer?.cancel()
        updateStats()
        timer = Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateStats()
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
    private var pendingImmediateRefresh = false
    
    func updateStats() {
        if isUpdating {
            if isPopoverVisible {
                pendingImmediateRefresh = true
            }
            return
        }
        isUpdating = true
        
        let interval = updateInterval
        let isVisible = isPopoverVisible
        let options = TelemetryWorker.FetchOptions(
            cpu: isVisible ? showCPU : showMenuBarCPU,
            gpu: isVisible ? showGPU : showMenuBarGPU,
            memory: isVisible ? showMemory : showMenuBarMemory,
            disk: isVisible ? showDisk : showMenuBarDisk,
            network: isVisible ? showNetwork : showMenuBarNetwork,
            battery: isVisible ? showBattery : (hasBattery && showMenuBarBattery),
            advancedMemory: isVisible ? showAdvancedMemory : false,
            systemInfo: isVisible ? showSystemInfo : false,
            topCPU: isVisible ? showTopCPU : false,
            topGPU: isVisible ? showTopGPU : false,
            topMemory: isVisible ? showTopMemory : false
        )
        let totalMem = memoryTotal
        
        Task { [weak self] in
            guard let self = self else { return }
            let rawStats = await self.worker.fetchStats(interval: interval, options: options, totalMemory: totalMem)
            let mergedStats = rawStats.mergingPopoverData(from: self.currentStats, options: options)
            if self.currentStats != mergedStats {
                self.currentStats = mergedStats
            }
            self.isUpdating = false
            if self.pendingImmediateRefresh {
                self.pendingImmediateRefresh = false
                self.updateStats()
            }
        }
    }
}
