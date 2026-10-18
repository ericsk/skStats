import Foundation
import Combine
import SwiftUI
import AppKit
import Darwin
import IOKit
import IOKit.ps
import ServiceManagement

@MainActor
class SystemMonitor: ObservableObject {
    @Published var currentStats: SystemStats? = nil
    @Published var isPopoverVisible: Bool = false {
        didSet {
            guard isPopoverVisible != oldValue else { return }
            if isPopoverVisible {
                if let latest = latestStats, currentStats != latest {
                    currentStats = latest
                }
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
    
    private var latestStats: SystemStats? = nil
    private var timer: AnyCancellable?
    private var debounceTask: Task<Void, Never>?
    private let worker = TelemetryWorker()
    private var cancellables = Set<AnyCancellable>()
    private var isScreenSleeping = false
    
    init() {
        self.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        self.hasBattery = checkBatteryPresence()
        
        // Observe thermal state changes instantly
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.thermalState = ProcessInfo.processInfo.thermalState
            }
            .store(in: &cancellables)
        
        // Pause telemetry timer completely when display or system sleeps to eliminate idle power impact
        let workspaceNC = NSWorkspace.shared.notificationCenter
        Publishers.Merge(
            workspaceNC.publisher(for: NSWorkspace.screensDidSleepNotification),
            workspaceNC.publisher(for: NSWorkspace.willSleepNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self = self else { return }
            self.isScreenSleeping = true
            self.timer?.cancel()
            self.timer = nil
        }
        .store(in: &cancellables)
        
        Publishers.Merge(
            workspaceNC.publisher(for: NSWorkspace.screensDidWakeNotification),
            workspaceNC.publisher(for: NSWorkspace.didWakeNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self = self else { return }
            self.isScreenSleeping = false
            self.setupTimer()
        }
        .store(in: &cancellables)
            
        startMonitoring(immediate: true)
    }
    
    private func checkBatteryPresence() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
               let type = desc[kIOPSTypeKey] as? String,
               type == kIOPSInternalBatteryType {
                return true
            }
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
        guard !isScreenSleeping else { return }
        updateStats()
        let interval = max(updateInterval, 1.0)
        // Allow 20% timer tolerance so macOS kernel coalesces wakeups for minimal Energy Impact
        timer = Timer.publish(every: interval, tolerance: interval * 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateStats()
            }
    }
    
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login status: \(error)")
        }
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }
    
    private var isUpdating = false
    private var pendingImmediateRefresh = false
    
    func updateStats() {
        guard !isScreenSleeping else { return }
        if isUpdating {
            if isPopoverVisible {
                pendingImmediateRefresh = true
            }
            return
        }
        
        let isVisible = isPopoverVisible
        let menuText = showMenuBarText
        let options = TelemetryWorker.FetchOptions(
            cpu: isVisible ? showCPU : (showMenuBarCPU && menuText),
            perCoreCPU: isVisible && showCPU,
            gpu: isVisible ? showGPU : (showMenuBarGPU && menuText),
            memory: isVisible ? showMemory : (showMenuBarMemory && menuText),
            disk: isVisible ? showDisk : (showMenuBarDisk && menuText),
            network: isVisible ? showNetwork : (showMenuBarNetwork && menuText),
            battery: hasBattery && (isVisible ? showBattery : showMenuBarBattery),
            detailedBattery: hasBattery && isVisible && showBattery,
            advancedMemory: isVisible && showAdvancedMemory,
            systemInfo: isVisible && showSystemInfo,
            topCPU: isVisible && showTopCPU,
            topGPU: isVisible && showTopGPU,
            topMemory: isVisible && showTopMemory
        )
        
        // Skip spawning background work entirely if no telemetry is requested (e.g. popover closed & only static icons shown)
        if !isVisible && !options.cpu && !options.gpu && !options.memory && !options.disk && !options.network && !options.battery && currentStats != nil {
            return
        }
        
        isUpdating = true
        let interval = updateInterval
        let totalMem = memoryTotal
        
        Task { [weak self] in
            guard let self = self else { return }
            let rawStats = await self.worker.fetchStats(interval: interval, options: options, totalMemory: totalMem)
            let mergedStats = rawStats.mergingPopoverData(from: self.latestStats ?? self.currentStats, options: options)
            self.latestStats = mergedStats
            
            if self.isPopoverVisible {
                if self.currentStats != mergedStats {
                    self.currentStats = mergedStats
                }
            } else if self.shouldPublishMenuBarUpdate(from: self.currentStats, to: mergedStats) {
                self.currentStats = mergedStats
            }
            
            self.isUpdating = false
            if self.pendingImmediateRefresh {
                self.pendingImmediateRefresh = false
                self.updateStats()
            }
        }
    }
    
    private func shouldPublishMenuBarUpdate(from oldStats: SystemStats?, to new: SystemStats) -> Bool {
        guard let old = oldStats else { return true }
        if showMenuBarText {
            if showMenuBarCPU && FormatUtils.formatPercentage(old.totalCPULoad) != FormatUtils.formatPercentage(new.totalCPULoad) {
                return true
            }
            if showMenuBarGPU && FormatUtils.formatPercentage(old.gpuLoad) != FormatUtils.formatPercentage(new.gpuLoad) {
                return true
            }
            if showMenuBarMemory {
                let denom = max(memoryTotal, 1)
                if FormatUtils.formatPercentage(old.memoryUsed / denom) != FormatUtils.formatPercentage(new.memoryUsed / denom) {
                    return true
                }
            }
            if showMenuBarNetwork {
                if FormatUtils.formatCompactRate(old.netUp) != FormatUtils.formatCompactRate(new.netUp) ||
                   FormatUtils.formatCompactRate(old.netDown) != FormatUtils.formatCompactRate(new.netDown) {
                    return true
                }
            }
            if showMenuBarDisk {
                if FormatUtils.formatCompactRate(old.diskRead) != FormatUtils.formatCompactRate(new.diskRead) ||
                   FormatUtils.formatCompactRate(old.diskWrite) != FormatUtils.formatCompactRate(new.diskWrite) {
                    return true
                }
            }
        }
        if hasBattery && showMenuBarBattery {
            if old.batteryIsCharging != new.batteryIsCharging ||
               FormatUtils.formatPercentage(old.batteryLevel) != FormatUtils.formatPercentage(new.batteryLevel) {
                return true
            }
        }
        return false
    }
}

