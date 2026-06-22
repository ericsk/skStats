import Foundation
import Combine
import SwiftUI
import Darwin
import IOKit
import IOKit.storage
import IOKit.network
import IOKit.ps
import ServiceManagement

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
    let topMemory: [TopProcess]
}

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
            topMemory: isVisible ? showTopMemory : false
        )
        let totalMem = memoryTotal
        
        Task {
            let stats = await worker.fetchStats(interval: interval, options: options, totalMemory: totalMem)
            await MainActor.run {
                self.currentStats = stats
                self.isUpdating = false
            }
        }
    }
}

// MARK: - Utilities

struct FormatUtils {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .memory
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func formatBytes(_ bytes: Double) -> String {
        if bytes < 1024 { return String(format: "%.0f B", bytes) }
        return byteFormatter.string(fromByteCount: Int64(bytes))
    }
    
    static func formatRate(_ bytesPerSecond: Double) -> String {
        let kbps = bytesPerSecond / 1024.0
        if kbps < 1024 {
            return String(format: "%.1f KB/s", kbps)
        }
        let mbps = kbps / 1024.0
        return String(format: "%.1f MB/s", mbps)
    }
    
    static func formatPercentage(_ value: Double) -> String {
        return String(format: "%.0f%%", value * 100)
    }
    
    static func formatCompactRate(_ bytesPerSecond: Double) -> String {
        let kbps = bytesPerSecond / 1024.0
        if kbps < 1024 {
            return String(format: "%.0fK", kbps)
        }
        let mbps = kbps / 1024.0
        return String(format: "%.1fM", mbps)
    }
}

final class TelemetryWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.skStats.telemetry", qos: .utility)
    private var previousCPUTicks: [processor_cpu_load_info] = []
    private var previousDiskBytesRead: UInt64 = 0
    private var previousDiskBytesWritten: UInt64 = 0
    private var previousNetworkBytesIn: UInt64 = 0
    private var previousNetworkBytesOut: UInt64 = 0
    private var previousProcessCPUTimes: [Int32: UInt64] = [:]
    private var nameCache: [Int32: String] = [:]
    private var lastUpdateTime: Date = Date()
    private var pruningCounter: Int = 0
    
    private struct ProcessCandidate {
        let pid: Int32
        let sortValue: Double
    }
    
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
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: SystemStats(cpuLoadPerCore: [], gpuLoad: 0, memoryUsed: 0, memorySwap: 0, memoryPressure: 0, diskRead: 0, diskWrite: 0, diskFree: 0, diskTotal: 0, netUp: 0, netDown: 0, batteryLevel: 0, batteryIsCharging: false, batteryPowerUsage: 0, batteryAdapterWattage: 0, batteryCycleCount: 0, batteryHealth: 0, batteryTemperature: 0, uptime: 0, topCPU: [], topMemory: []))
                    return
                }
                
                let now = Date()
                let realInterval = max(now.timeIntervalSince(self.lastUpdateTime), 0.1)
                self.lastUpdateTime = now
                
                var cpu: [Double] = []
                var gpu: Double = 0
                var mem: Double = 0
                var swap: Double = 0
                var pressure: Double = 0
                var disk: (read: Double, write: Double) = (0, 0)
                var diskSpace: (free: Int64, total: Int64) = (0, 0)
                var net: (up: Double, down: Double) = (0, 0)
                var battery: (level: Double, isCharging: Bool, usage: Double, adapter: Int, cycles: Int, health: Double, temperature: Double) = (0, false, 0, 0, 0, 0, 0)
                var uptime: TimeInterval = 0
                var topCPU: [TopProcess] = []
                var topMem: [TopProcess] = []
                
                if options.cpu { cpu = self.fetchCPU() }
                if options.gpu { gpu = self.fetchGPU() }
                if options.memory || options.topMemory || options.advancedMemory {
                    mem = self.fetchMemory(totalMemory: totalMemory)
                    if options.advancedMemory {
                        swap = self.fetchSwap()
                        pressure = self.fetchMemoryPressure()
                    }
                }
                if options.disk { disk = self.fetchDisk(interval: realInterval) }
                if options.systemInfo {
                    diskSpace = self.fetchDiskSpace()
                    uptime = self.fetchUptime()
                }
                if options.network { net = self.fetchNetwork64(interval: realInterval) }
                if options.battery { battery = self.fetchBattery() }
                if options.topCPU || options.topMemory {
                    let results = self.fetchTopProcesses(interval: realInterval, showCPU: options.topCPU, showMemory: options.topMemory)
                    topCPU = results.cpu
                    topMem = results.memory
                }
                
                let stats = SystemStats(
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
                    batteryTemperature: battery.temperature,
                    uptime: uptime,
                    topCPU: topCPU,
                    topMemory: topMem
                )
                
                continuation.resume(returning: stats)
            }
        }
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
        
        let numCPUs = Int(numCPUsU)
        var currentLoad: [Double] = []
        var newTicks: [processor_cpu_load_info] = []
        
        for i in 0..<numCPUs {
            let offset = i * Int(CPU_STATE_MAX)
            let user = UInt32(cpuInfo[offset + Int(CPU_STATE_USER)])
            let system = UInt32(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt32(cpuInfo[offset + Int(CPU_STATE_NICE)])
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
                if let stats = IORegistryEntryCreateCFProperty(drive, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
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
    
    private func fetchNetwork64(interval: Double) -> (up: Double, down: Double) {
        var mib = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        if sysctl(&mib, 6, nil, &len, nil, 0) < 0 {
            return fetchNetwork(interval: interval)
        }
        
        var buf = [CChar](repeating: 0, count: len)
        if sysctl(&mib, 6, &buf, &len, nil, 0) < 0 {
            return fetchNetwork(interval: interval)
        }
        
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        
        buf.withUnsafeBufferPointer { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }
            var offset = 0
            while offset < len {
                let rawPtr = UnsafeRawPointer(baseAddress).advanced(by: offset)
                let ifm = rawPtr.load(as: if_msghdr2.self)
                
                if ifm.ifm_type == UInt8(RTM_IFINFO2) {
                    bytesIn += ifm.ifm_data.ifi_ibytes
                    bytesOut += ifm.ifm_data.ifi_obytes
                }
                offset += Int(ifm.ifm_msglen)
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
    
    private func fetchBattery() -> (level: Double, isCharging: Bool, usage: Double, adapter: Int, cycles: Int, health: Double, temperature: Double) {
        var level: Double = 0
        var isCharging: Bool = false
        var cycles: Int = 0
        var health: Double = 0
        var usage: Double = 0
        var adapterWattage: Int = 0
        var temperature: Double = 0.0
        
        let masterPort: mach_port_t = kIOMainPortDefault
        let matchingDict = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(masterPort, matchingDict, &iterator) == kIOReturnSuccess {
            let batteryService = IOIteratorNext(iterator)
            if batteryService != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(batteryService, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dict = props?.takeRetainedValue() as? [String: Any] {
                    
                    let maxCap = (dict["MaxCapacity"] as? NSNumber)?.doubleValue ?? 100.0
                    let curCap = (dict["CurrentCapacity"] as? NSNumber)?.doubleValue ?? 0.0
                    level = maxCap > 0 ? curCap / maxCap : 0.0
                    
                    isCharging = dict["IsCharging"] as? Bool ?? false
                    if !isCharging {
                        if let isChargingNum = dict["IsCharging"] as? NSNumber {
                            isCharging = isChargingNum.boolValue
                        }
                    }
                    
                    cycles = (dict["CycleCount"] as? NSNumber)?.intValue ?? 0
                    
                    let designCap = (dict["DesignCapacity"] as? NSNumber)?.doubleValue ?? 0.0
                    let rawMaxCap = (dict["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue ?? maxCap
                    if designCap > 0 {
                        if rawMaxCap <= 100 && designCap > 100 {
                            health = 1.0
                        } else {
                            health = rawMaxCap / designCap
                        }
                    }
                    
                    if let amperage = (dict["Amperage"] as? NSNumber)?.int64Value,
                       let voltage = (dict["Voltage"] as? NSNumber)?.int64Value {
                        usage = Double(amperage) * Double(voltage) / 1_000_000.0 // mA * mV = uW -> W
                    }
                    
                    if let adapterDetails = dict["AdapterDetails"] as? [String: Any],
                       let watts = adapterDetails["Watts"] as? Int {
                        adapterWattage = watts
                    }
                    
                    if let tempRaw = (dict["Temperature"] as? NSNumber)?.doubleValue {
                        temperature = tempRaw / 100.0 // centi-Celsius
                    }
                }
                IOObjectRelease(batteryService)
            }
            IOObjectRelease(iterator)
        }
        
        return (level, isCharging, usage, adapterWattage, cycles, health, temperature)
    }
    
    private func fetchGPU() -> Double {
        var matchIterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching("IOAccelerator")
        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &matchIterator) == kIOReturnSuccess {
            var service: io_registry_entry_t = IOIteratorNext(matchIterator)
            while service != 0 {
                if let perfStats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                    if let utilization = (perfStats["Device Utilization %"] as? NSNumber) ?? (perfStats["Device Utilization"] as? NSNumber) {
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
    
    private func fetchTopProcesses(interval: Double, showCPU: Bool, showMemory: Bool) -> (cpu: [TopProcess], memory: [TopProcess]) {
        let pids = getPIDs()
        var cpuCandidates: [ProcessCandidate] = []
        var memCandidates: [ProcessCandidate] = []
        cpuCandidates.reserveCapacity(pids.count)
        memCandidates.reserveCapacity(pids.count)
        var currentTimes: [Int32: UInt64] = [:]
        
        // Prune name cache and CPU times for dead processes less frequently
        pruningCounter += 1
        if pruningCounter >= 10 {
            let currentPidsSet = Set(pids)
            nameCache = nameCache.filter { currentPidsSet.contains($0.key) }
            previousProcessCPUTimes = previousProcessCPUTimes.filter { currentPidsSet.contains($0.key) }
            pruningCounter = 0
        }
        
        for pid in pids {
            if pid <= 0 { continue }
            var usage = proc_taskinfo()
            let size = MemoryLayout<proc_taskinfo>.size
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &usage, Int32(size)) == Int32(size) {
                if showCPU {
                    let totalTime = usage.pti_total_user + usage.pti_total_system
                    currentTimes[pid] = totalTime
                    if let prevTime = previousProcessCPUTimes[pid], interval > 0 {
                        let delta = Double(totalTime >= prevTime ? totalTime - prevTime : 0)
                        let percentage = (delta / 1_000_000_000.0) / interval * 100.0
                        if percentage > 0.1 {
                            cpuCandidates.append(ProcessCandidate(pid: pid, sortValue: percentage))
                        }
                    }
                }
                
                if showMemory {
                    let mem = usage.pti_resident_size
                    memCandidates.append(ProcessCandidate(pid: pid, sortValue: Double(mem)))
                }
            }
        }
        
        if showCPU {
            self.previousProcessCPUTimes = currentTimes
        }
        
        // Sort and select top candidates
        let topCPUCandidates = cpuCandidates.sorted { $0.sortValue > $1.sortValue }.prefix(3)
        let topMemCandidates = memCandidates.sorted { $0.sortValue > $1.sortValue }.prefix(3)
        
        let resolveName = { (pid: Int32) -> String in
            if let cached = self.nameCache[pid] { return cached }
            let name = self.getName(pid: pid)
            self.nameCache[pid] = name
            return name
        }
        
        return (
            cpu: topCPUCandidates.map { TopProcess(name: resolveName($0.pid), value: String(format: "%.1f%%", $0.sortValue), sortValue: $0.sortValue) },
            memory: topMemCandidates.map { item -> TopProcess in
                let mb = item.sortValue / 1024.0 / 1024.0
                let displayValue = mb > 1024 ? String(format: "%.1f GB", mb / 1024.0) : String(format: "%.0f MB", mb)
                return TopProcess(name: resolveName(item.pid), value: displayValue, sortValue: item.sortValue)
            }
        )
    }
    
    private func getPIDs() -> [Int32] {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        let count = Int(bufferSize) / MemoryLayout<Int32>.size
        var pids = [Int32](repeating: 0, count: count)
        let actualBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(bufferSize))
        if actualBytes <= 0 { return [] }
        let actualCount = Int(actualBytes) / MemoryLayout<Int32>.size
        return Array(pids.prefix(actualCount))
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
