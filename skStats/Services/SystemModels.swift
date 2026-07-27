import Foundation

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "Memory"
    case network = "Network"
    case disk = "Disk"
    case battery = "Battery"
    var id: String { self.rawValue }
}

struct TopProcess: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let value: String
    let sortValue: Double
    
    static func == (lhs: TopProcess, rhs: TopProcess) -> Bool {
        return lhs.name == rhs.name && lhs.value == rhs.value && lhs.sortValue == rhs.sortValue
    }
}

struct SystemStats: Equatable {
    let cpuLoadPerCore: [Double]
    var totalCPULoad: Double {
        guard !cpuLoadPerCore.isEmpty else { return 0.0 }
        return cpuLoadPerCore.reduce(0, +) / Double(cpuLoadPerCore.count)
    }
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
}
