import Foundation

struct TopProcess: Identifiable, Equatable, Sendable {
    let pid: Int32
    let name: String
    let value: String
    let sortValue: Double
    
    var id: Int32 { pid }
}

struct SystemStats: Equatable, Sendable {
    let cpuLoadPerCore: [Double]
    let cpuUserLoad: Double
    let cpuSystemLoad: Double
    let totalCPULoad: Double
    let gpuLoad: Double
    let memoryUsed: Double
    let memorySwap: Double
    let memoryPressure: Double
    let diskRead: Double
    let diskWrite: Double
    let diskFree: Int64
    let diskTotal: Int64
    let netUp: Double
    let netDown: Double
    let batteryLevel: Double
    let batteryIsCharging: Bool
    let batteryPowerUsage: Double
    let batteryAdapterWattage: Int
    let batteryCycleCount: Int
    let batteryHealth: Double
    let batteryTemperature: Double
    let uptime: TimeInterval
    let topCPU: [TopProcess]
    let topGPU: [TopProcess]
    let topMemory: [TopProcess]
    
    /// Preserves previously cached popover-only metrics when performing lightweight background updates while the popover is closed.
    func mergingPopoverData(from previous: SystemStats?, options: TelemetryWorker.FetchOptions) -> SystemStats {
        guard let previous = previous else { return self }
        return SystemStats(
            cpuLoadPerCore: options.perCoreCPU ? self.cpuLoadPerCore : previous.cpuLoadPerCore,
            cpuUserLoad: options.cpu ? self.cpuUserLoad : previous.cpuUserLoad,
            cpuSystemLoad: options.cpu ? self.cpuSystemLoad : previous.cpuSystemLoad,
            totalCPULoad: options.cpu ? self.totalCPULoad : previous.totalCPULoad,
            gpuLoad: options.gpu ? self.gpuLoad : previous.gpuLoad,
            memoryUsed: (options.memory || options.topMemory || options.advancedMemory) ? self.memoryUsed : previous.memoryUsed,
            memorySwap: options.advancedMemory ? self.memorySwap : previous.memorySwap,
            memoryPressure: options.advancedMemory ? self.memoryPressure : previous.memoryPressure,
            diskRead: options.disk ? self.diskRead : previous.diskRead,
            diskWrite: options.disk ? self.diskWrite : previous.diskWrite,
            diskFree: options.systemInfo ? self.diskFree : previous.diskFree,
            diskTotal: options.systemInfo ? self.diskTotal : previous.diskTotal,
            netUp: options.network ? self.netUp : previous.netUp,
            netDown: options.network ? self.netDown : previous.netDown,
            batteryLevel: options.battery ? self.batteryLevel : previous.batteryLevel,
            batteryIsCharging: options.battery ? self.batteryIsCharging : previous.batteryIsCharging,
            batteryPowerUsage: options.detailedBattery ? self.batteryPowerUsage : previous.batteryPowerUsage,
            batteryAdapterWattage: options.detailedBattery ? self.batteryAdapterWattage : previous.batteryAdapterWattage,
            batteryCycleCount: options.detailedBattery ? self.batteryCycleCount : previous.batteryCycleCount,
            batteryHealth: options.detailedBattery ? self.batteryHealth : previous.batteryHealth,
            batteryTemperature: options.detailedBattery ? self.batteryTemperature : previous.batteryTemperature,
            uptime: options.systemInfo ? self.uptime : previous.uptime,
            topCPU: options.topCPU ? self.topCPU : previous.topCPU,
            topGPU: options.topGPU ? self.topGPU : previous.topGPU,
            topMemory: options.topMemory ? self.topMemory : previous.topMemory
        )
    }
}

