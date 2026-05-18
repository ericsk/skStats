import Foundation
import Combine
import SwiftUI
import Darwin
import IOKit
import IOKit.storage
import IOKit.network
import IOKit.ps

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
    let uptime: TimeInterval
    let topCPU: [TopProcess]
    let topMemory: [TopProcess]
}

@MainActor
class SystemMonitor: ObservableObject {
    @Published var currentStats: SystemStats? = nil
    @Published var isPopoverVisible: Bool = false
    @Published var memoryTotal: Double = 0.0
    
    @AppStorage("showCPU") var showCPU: Bool = true
    @AppStorage("showGPU") var showGPU: Bool = true
    @AppStorage("showMemory") var showMemory: Bool = true
    @AppStorage("showDisk") var showDisk: Bool = true
    @AppStorage("showNetwork") var showNetwork: Bool = true
    @AppStorage("showTopCPU") var showTopCPU: Bool = true
    @AppStorage("showTopMemory") var showTopMemory: Bool = true
    @AppStorage("showBattery") var showBattery: Bool = true
    @AppStorage("showAdvancedMemory") var showAdvancedMemory: Bool = true
    @AppStorage("showSystemInfo") var showSystemInfo: Bool = true
    
    @AppStorage("showMenuBarMode") var showMenuBarMode: MenuBarDisplayMode = .cpu
    @AppStorage("showMenuBarText") var showMenuBarText: Bool = true
    @AppStorage("updateInterval") var updateInterval: Double = 3.0
    
    private var timer: AnyCancellable?
    private let worker = TelemetryWorker()
    
    init() {
        self.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        startMonitoring()
    }
    
    func startMonitoring() {
        timer?.cancel()
        updateStats()
        timer = Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateStats()
            }
    }
    
    func updateStats() {
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
            topMemory: isVisible ? showTopMemory : false
        )
        let totalMem = memoryTotal
        
        Task {
            let stats = await worker.fetchStats(interval: interval, options: options, totalMemory: totalMem)
            self.currentStats = stats
        }
    }
}

// MARK: - Utilities

struct FormatUtils {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .memory
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func formatBytes(_ bytes: Double) -> String {
        if bytes < 1024 { return String(format: "%.0f B", bytes) }
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

actor TelemetryWorker {
    private var previousCPUTicks: [processor_cpu_load_info] = []
    private var previousDiskBytesRead: UInt64 = 0
    private var previousDiskBytesWritten: UInt64 = 0
    private var previousNetworkBytesIn: UInt64 = 0
    private var previousNetworkBytesOut: UInt64 = 0
    private var previousProcessCPUTimes: [Int32: UInt64] = [:]
    private var lastUpdateTime: Date = Date()
    
    struct FetchOptions {
        let cpu: Bool
        let gpu: Bool
        let memory: Bool
        let disk: Bool
        let network: Bool
        let battery: Bool
        let advancedMemory: Bool
        let systemInfo: Bool
        let topCPU: Bool
        let topMemory: Bool
    }
    
    func fetchStats(interval: Double, options: FetchOptions, totalMemory: Double) async -> SystemStats {
        var cpu: [Double] = []
        var gpu: Double = 0
        var mem: Double = 0
        var swap: Double = 0
        var pressure: Double = 0
        var disk: (read: Double, write: Double) = (0, 0)
        var diskSpace: (free: Int64, total: Int64) = (0, 0)
        var net: (up: Double, down: Double) = (0, 0)
        var battery: (level: Double, isCharging: Bool, usage: Double, adapter: Int, cycles: Int, health: Double) = (0, false, 0, 0, 0, 0)
        var uptime: TimeInterval = 0
        var topCPU: [TopProcess] = []
        var topMem: [TopProcess] = []
        
        await withTaskGroup(of: Void.self) { group in
            if options.cpu {
                group.addTask { cpu = await self.fetchCPU() }
            }
            if options.gpu {
                group.addTask { gpu = await self.fetchGPU() }
            }
            if options.memory || options.topMemory || options.advancedMemory {
                group.addTask {
                    mem = await self.fetchMemory(totalMemory: totalMemory)
                    if options.advancedMemory {
                        swap = await self.fetchSwap()
                        pressure = await self.fetchMemoryPressure()
                    }
                }
            }
            if options.disk {
                group.addTask { disk = await self.fetchDisk(interval: interval) }
            }
            if options.systemInfo {
                group.addTask {
                    diskSpace = await self.fetchDiskSpace()
                    uptime = await self.fetchUptime()
                }
            }
            if options.network {
                group.addTask { net = await self.fetchNetwork(interval: interval) }
            }
            if options.battery {
                group.addTask { battery = await self.fetchBattery() }
            }
            if options.topCPU || options.topMemory {
                group.addTask {
                    let results = await self.fetchTopProcesses(showCPU: options.topCPU, showMemory: options.topMemory)
                    topCPU = results.cpu
                    topMem = results.memory
                }
            }
        }
        
        lastUpdateTime = Date()
        
        return SystemStats(
            cpuLoadPerCore: cpu,
            gpuLoad: gpu,
            memoryUsed: mem,
            memorySwap: swap,
            memoryPressure: pressure,
            diskRead: disk.read,
            diskWrite: disk.write,
            diskFree: diskSpace.free,
            diskTotal: diskSpace.total,
            netUp: net.up,
            netDown: net.down,
            batteryLevel: battery.level,
            batteryIsCharging: battery.isCharging,
            batteryPowerUsage: battery.usage,
            batteryAdapterWattage: battery.adapter,
            batteryCycleCount: battery.cycles,
            batteryHealth: battery.health,
            uptime: uptime,
            topCPU: topCPU,
            topMemory: topMem
        )
    }
    
    private func fetchSwap() -> Double {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 {
            return Double(usage.xsu_used)
        }
        return 0
    }
    
    private func fetchMemoryPressure() -> Double {
        var pressure: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_level", &pressure, &size, nil, 0) == 0 {
            return Double(pressure)
        }
        return 0
    }
    
    private func fetchDiskSpace() -> (free: Int64, total: Int64) {
        let fileManager = FileManager.default
        let path = "/"
        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: path)
            let free = attrs[.systemFreeSize] as? Int64 ?? 0
            let total = attrs[.systemSize] as? Int64 ?? 0
            return (free, total)
        } catch {
            return (0, 0)
        }
    }
    
    private func fetchUptime() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }
    
    private func fetchCPU() -> [Double] {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else { return [] }
        
        let infoPointer = cpuInfo.withMemoryRebound(to: integer_t.self, capacity: Int(numCpuInfo)) { $0 }
        let numCPUs = Int(numCPUsU)
        var currentLoad: [Double] = []
        var newTicks: [processor_cpu_load_info] = []
        
        for i in 0..<numCPUs {
            let offset = i * Int(CPU_STATE_MAX)
            let user = UInt32(infoPointer[offset + Int(CPU_STATE_USER)])
            let system = UInt32(infoPointer[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(infoPointer[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt32(infoPointer[offset + Int(CPU_STATE_NICE)])
            let tick = processor_cpu_load_info(cpu_ticks: (user, system, idle, nice))
            newTicks.append(tick)
            
            if previousCPUTicks.count == numCPUs {
                let prev = previousCPUTicks[i]
                let totalDiff = Double(user + system + idle + nice) - Double(prev.cpu_ticks.0 + prev.cpu_ticks.1 + prev.cpu_ticks.2 + prev.cpu_ticks.3)
                let activeDiff = Double(user + system + nice) - Double(prev.cpu_ticks.0 + prev.cpu_ticks.1 + prev.cpu_ticks.3)
                let load: Double = totalDiff > 0.0 ? min(max(activeDiff / totalDiff, 0.0), 1.0) : 0.0
                currentLoad.append(load)
            } else {
                currentLoad.append(0.0)
            }
        }
        self.previousCPUTicks = newTicks
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        return currentLoad
    }
    
    private func fetchMemory(totalMemory: Double) -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let active = Double(stats.active_count) * Double(vm_page_size)
            let wire = Double(stats.wire_count) * Double(vm_page_size)
            let compressed = Double(stats.compressor_page_count) * Double(vm_page_size)
            return min(active + wire + compressed, totalMemory)
        }
        return 0
    }
    
    private func fetchDisk(interval: Double) -> (read: Double, write: Double) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var matchIterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching("IOBlockStorageDriver")
        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &matchIterator) == kIOReturnSuccess {
            var drive: io_registry_entry_t = IOIteratorNext(matchIterator)
            while drive != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(drive, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let props = properties?.takeRetainedValue() as? [String: Any],
                   let stats = props["Statistics"] as? [String: Any] {
                    if let readBytes = stats["Bytes (Read)"] as? NSNumber { totalRead += readBytes.uint64Value }
                    if let writeBytes = stats["Bytes (Write)"] as? NSNumber { totalWrite += writeBytes.uint64Value }
                }
                IOObjectRelease(drive)
                drive = IOIteratorNext(matchIterator)
            }
            IOObjectRelease(matchIterator)
        }
        var readRate: Double = 0
        var writeRate: Double = 0
        if previousDiskBytesRead > 0 {
            readRate = Double(totalRead >= previousDiskBytesRead ? totalRead - previousDiskBytesRead : 0) / interval
            writeRate = Double(totalWrite >= previousDiskBytesWritten ? totalWrite - previousDiskBytesWritten : 0) / interval
        }
        self.previousDiskBytesRead = totalRead
        self.previousDiskBytesWritten = totalWrite
        return (readRate, writeRate)
    }
    
    private func fetchNetwork(interval: Double) -> (up: Double, down: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if let data = ptr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    bytesIn += UInt64(networkData.ifi_ibytes)
                    bytesOut += UInt64(networkData.ifi_obytes)
                }
            }
        }
        var up: Double = 0
        var down: Double = 0
        if previousNetworkBytesIn > 0 {
            down = Double(bytesIn >= previousNetworkBytesIn ? bytesIn - previousNetworkBytesIn : 0) / interval
            up = Double(bytesOut >= previousNetworkBytesOut ? bytesOut - previousNetworkBytesOut : 0) / interval
        }
        self.previousNetworkBytesIn = bytesIn
        self.previousNetworkBytesOut = bytesOut
        return (up, down)
    }
    
    private func fetchBattery() -> (level: Double, isCharging: Bool, usage: Double, adapter: Int, cycles: Int, health: Double) {
        var level: Double = 0
        var isCharging: Bool = false
        var cycles: Int = 0
        var health: Double = 0
        var usage: Double = 0
        var adapterWattage: Int = 0
        
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] {
                level = (description[kIOPSCurrentCapacityKey] as? Double ?? 0) / (description[kIOPSMaxCapacityKey] as? Double ?? 100)
                isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            }
        }
        
        var masterPort: mach_port_t = kIOMainPortDefault
        var matchingDict = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(masterPort, matchingDict, &iterator) == kIOReturnSuccess {
            let batteryService = IOIteratorNext(iterator)
            if batteryService != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(batteryService, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dict = props?.takeRetainedValue() as? [String: Any] {
                    cycles = dict["CycleCount"] as? Int ?? 0
                    if let maxCap = dict["MaxCapacity"] as? Double, let designCap = dict["DesignCapacity"] as? Double {
                        health = maxCap / designCap
                    }
                    if let amperage = (dict["Amperage"] as? NSNumber)?.int64Value,
                       let voltage = (dict["Voltage"] as? NSNumber)?.int64Value {
                        usage = Double(amperage) * Double(voltage) / 1_000_000.0 // mA * mV = uW -> W
                    }
                    if let adapterDetails = dict["AdapterDetails"] as? [String: Any],
                       let watts = adapterDetails["Watts"] as? Int {
                        adapterWattage = watts
                    }
                }
                IOObjectRelease(batteryService)
            }
            IOObjectRelease(iterator)
        }
        
        return (level, isCharging, usage, adapterWattage, cycles, health)
    }
    
    private func fetchGPU() -> Double {
        var matchIterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching("IOAccelerator")
        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &matchIterator) == kIOReturnSuccess {
            var service: io_registry_entry_t = IOIteratorNext(matchIterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let props = properties?.takeRetainedValue() as? [String: Any],
                   let perfStats = props["PerformanceStatistics"] as? [String: Any] {
                    if let utilization = perfStats["Device Utilization %"] as? NSNumber {
                        IOObjectRelease(service)
                        IOObjectRelease(matchIterator)
                        return utilization.doubleValue / 100.0
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(matchIterator)
            }
            IOObjectRelease(matchIterator)
        }
        return 0
    }
    
    private func fetchTopProcesses(showCPU: Bool, showMemory: Bool) -> (cpu: [TopProcess], memory: [TopProcess]) {
        let pids = getPIDs()
        var cpuProcesses: [TopProcess] = []
        var memProcesses: [TopProcess] = []
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastUpdateTime)
        var currentTimes: [Int32: UInt64] = [:]
        
        for pid in pids {
            var usage = proc_taskinfo()
            let size = MemoryLayout<proc_taskinfo>.size
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &usage, Int32(size)) == Int32(size) {
                if showCPU {
                    let totalTime = usage.pti_total_user + usage.pti_total_system
                    currentTimes[pid] = totalTime
                    if let prevTime = previousProcessCPUTimes[pid], timeInterval > 0 {
                        let delta = Double(totalTime >= prevTime ? totalTime - prevTime : 0)
                        let percentage = (delta / 1_000_000_000.0) / timeInterval * 100.0
                        if percentage > 0.1 {
                            cpuProcesses.append(TopProcess(name: getName(pid: pid), value: String(format: "%.1f%%", percentage), sortValue: percentage))
                        }
                    }
                }
                
                if showMemory {
                    let mem = usage.pti_resident_size
                    let mb = Double(mem) / 1024.0 / 1024.0
                    let formatValue = mb > 1024 ? String(format: "%.1f GB", mb / 1024.0) : String(format: "%.0f MB", mb)
                    memProcesses.append(TopProcess(name: getName(pid: pid), value: formatValue, sortValue: Double(mem)))
                }
            }
        }
        
        if showCPU {
            self.previousProcessCPUTimes = currentTimes
        }
        
        return (
            cpu: Array(cpuProcesses.sorted { $0.sortValue > $1.sortValue }.prefix(3)),
            memory: Array(memProcesses.sorted { $0.sortValue > $1.sortValue }.prefix(3))
        )
    }
    
    private func getPIDs() -> [Int32] {
        let numberOfProcesses = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        var pids = [Int32](repeating: 0, count: Int(numberOfProcesses))
        let bufferSize = Int32(numberOfProcesses) * Int32(MemoryLayout<Int32>.size)
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        if count <= 0 { return [] }
        return Array(pids.prefix(Int(count) / MemoryLayout<Int32>.size))
    }
    
    private func getName(pid: Int32) -> String {
        let maxPath = 1024
        var buffer = [UInt8](repeating: 0, count: maxPath)
        if proc_name(pid, &buffer, UInt32(maxPath)) > 0 {
            return String(cString: buffer)
        }
        return "Unknown"
    }
}
