import Foundation
import Combine
import Darwin
import IOKit
import IOKit.storage
import IOKit.network

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "Memory"
    case network = "Network"
    case disk = "Disk"
    var id: String { self.rawValue }
}

struct TopProcess: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let sortValue: Double
}

struct SystemStats {
    let cpuLoadPerCore: [Double]
    let gpuLoad: Double
    let memoryUsed: Double
    let diskRead: Double
    let diskWrite: Double
    let netUp: Double
    let netDown: Double
    let topCPU: [TopProcess]
    let topMemory: [TopProcess]
}

@MainActor
class SystemMonitor: ObservableObject {
    @Published var cpuLoadPerCore: [Double] = []
    var totalCPULoad: Double {
        guard !cpuLoadPerCore.isEmpty else { return 0.0 }
        return cpuLoadPerCore.reduce(0, +) / Double(cpuLoadPerCore.count)
    }
    @Published var gpuLoad: Double = 0.0
    @Published var memoryUsed: Double = 0.0
    @Published var memoryTotal: Double = 0.0
    @Published var diskReadRate: Double = 0.0
    @Published var diskWriteRate: Double = 0.0
    @Published var networkUploadRate: Double = 0.0
    @Published var networkDownloadRate: Double = 0.0
    
    @Published var showCPU: Bool = true
    @Published var showGPU: Bool = true
    @Published var showMemory: Bool = true
    @Published var showDisk: Bool = true
    @Published var showNetwork: Bool = true
    @Published var showTopCPU: Bool = true
    @Published var showTopMemory: Bool = true
    
    @Published var showMenuBarMode: MenuBarDisplayMode = .cpu
    @Published var showMenuBarText: Bool = true
    
    @Published var topCPU: [TopProcess] = []
    @Published var topMemory: [TopProcess] = []
    @Published var updateInterval: Double = 3.0
    
    private var timer: AnyCancellable?
    private let worker = TelemetryWorker()
    
    init() {
        self.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        loadSettings()
        startMonitoring()
    }
    
    func loadSettings() {
        let defaults = UserDefaults.standard
        showCPU = defaults.object(forKey: "showCPU") == nil ? true : defaults.bool(forKey: "showCPU")
        showGPU = defaults.object(forKey: "showGPU") == nil ? true : defaults.bool(forKey: "showGPU")
        showMemory = defaults.object(forKey: "showMemory") == nil ? true : defaults.bool(forKey: "showMemory")
        showDisk = defaults.object(forKey: "showDisk") == nil ? true : defaults.bool(forKey: "showDisk")
        showNetwork = defaults.object(forKey: "showNetwork") == nil ? true : defaults.bool(forKey: "showNetwork")
        showTopCPU = defaults.object(forKey: "showTopCPU") == nil ? true : defaults.bool(forKey: "showTopCPU")
        showTopMemory = defaults.object(forKey: "showTopMemory") == nil ? true : defaults.bool(forKey: "showTopMemory")
        
        if let modeStr = defaults.string(forKey: "showMenuBarMode"),
           let mode = MenuBarDisplayMode(rawValue: modeStr) {
            showMenuBarMode = mode
        }
        showMenuBarText = defaults.object(forKey: "showMenuBarText") == nil ? true : defaults.bool(forKey: "showMenuBarText")
        if defaults.object(forKey: "updateInterval") != nil {
            updateInterval = defaults.double(forKey: "updateInterval")
        }
    }
    
    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(showCPU, forKey: "showCPU")
        defaults.set(showGPU, forKey: "showGPU")
        defaults.set(showMemory, forKey: "showMemory")
        defaults.set(showDisk, forKey: "showDisk")
        defaults.set(showNetwork, forKey: "showNetwork")
        defaults.set(showTopCPU, forKey: "showTopCPU")
        defaults.set(showTopMemory, forKey: "showTopMemory")
        defaults.set(showMenuBarMode.rawValue, forKey: "showMenuBarMode")
        defaults.set(showMenuBarText, forKey: "showMenuBarText")
        defaults.set(updateInterval, forKey: "updateInterval")
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
        let sCPU = showTopCPU
        let sMem = showTopMemory
        let totalMem = memoryTotal
        
        Task {
            let stats = await worker.fetchStats(interval: interval, showTopCPU: sCPU, showTopMemory: sMem, totalMemory: totalMem)
            self.cpuLoadPerCore = stats.cpuLoadPerCore
            self.gpuLoad = stats.gpuLoad
            self.memoryUsed = stats.memoryUsed
            self.diskReadRate = stats.diskRead
            self.diskWriteRate = stats.diskWrite
            self.networkDownloadRate = stats.netDown
            self.networkUploadRate = stats.netUp
            self.topCPU = stats.topCPU
            self.topMemory = stats.topMemory
        }
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
    
    func fetchStats(interval: Double, showTopCPU: Bool, showTopMemory: Bool, totalMemory: Double) -> SystemStats {
        let cpu = fetchCPU()
        let gpu = fetchGPU()
        let mem = fetchMemory(totalMemory: totalMemory)
        let disk = fetchDisk(interval: interval)
        let net = fetchNetwork(interval: interval)
        let topCPU = showTopCPU ? fetchTopCPUProcesses() : []
        let topMem = showTopMemory ? fetchTopMemoryProcesses() : []
        
        lastUpdateTime = Date()
        
        return SystemStats(
            cpuLoadPerCore: cpu,
            gpuLoad: gpu,
            memoryUsed: mem,
            diskRead: disk.read,
            diskWrite: disk.write,
            netUp: net.up,
            netDown: net.down,
            topCPU: topCPU,
            topMemory: topMem
        )
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
    
    private func fetchTopCPUProcesses() -> [TopProcess] {
        let pids = getPIDs()
        var processes: [TopProcess] = []
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastUpdateTime)
        var currentTimes: [Int32: UInt64] = [:]
        
        for pid in pids {
            var usage = proc_taskinfo()
            let size = MemoryLayout<proc_taskinfo>.size
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &usage, Int32(size)) == Int32(size) {
                let totalTime = usage.pti_total_user + usage.pti_total_system
                currentTimes[pid] = totalTime
                if let prevTime = previousProcessCPUTimes[pid], timeInterval > 0 {
                    let delta = Double(totalTime >= prevTime ? totalTime - prevTime : 0)
                    let percentage = (delta / 1_000_000_000.0) / timeInterval * 100.0
                    if percentage > 0.1 {
                        processes.append(TopProcess(name: getName(pid: pid), value: String(format: "%.1f%%", percentage), sortValue: percentage))
                    }
                }
            }
        }
        self.previousProcessCPUTimes = currentTimes
        return Array(processes.sorted { $0.sortValue > $1.sortValue }.prefix(3))
    }
    
    private func fetchTopMemoryProcesses() -> [TopProcess] {
        let pids = getPIDs()
        var processes: [TopProcess] = []
        for pid in pids {
            var usage = proc_taskinfo()
            let size = MemoryLayout<proc_taskinfo>.size
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &usage, Int32(size)) == Int32(size) {
                let mem = usage.pti_resident_size
                let mb = Double(mem) / 1024.0 / 1024.0
                let formatValue = mb > 1024 ? String(format: "%.1f GB", mb / 1024.0) : String(format: "%.0f MB", mb)
                processes.append(TopProcess(name: getName(pid: pid), value: formatValue, sortValue: Double(mem)))
            }
        }
        return Array(processes.sorted { $0.sortValue > $1.sortValue }.prefix(3))
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
