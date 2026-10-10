import Foundation
import Darwin
import IOKit
import IOKit.storage
import IOKit.network
import IOKit.ps

actor TelemetryWorker {
    private var previousCPUTicks: [processor_cpu_load_info] = []
    private var hasPreviousDiskData: Bool = false
    private var previousDiskBytesRead: UInt64 = 0
    private var previousDiskBytesWritten: UInt64 = 0
    private var hasPreviousNetworkData: Bool = false
    private var previousNetworkBytesIn: UInt64 = 0
    private var previousNetworkBytesOut: UInt64 = 0
    private var previousProcessCPUTimes: [Int32: UInt64] = [:]
    private var previousProcessGPUTimes: [Int32: UInt64] = [:]
    private var nameCache: [Int32: String] = [:]
    private var lastUpdateTime: Date = Date()
    private var pruningCounter: Int = 0
    
    private var gpuServices: [io_registry_entry_t]
    private var batteryServices: [io_registry_entry_t]
    private let ticksToNanoseconds: Double
    
    private struct ProcessCandidate {
        let pid: Int32
        let sortValue: Double
    }
    
    struct FetchOptions: Sendable {
        let cpu: Bool
        let gpu: Bool
        let memory: Bool
        let disk: Bool
        let network: Bool
        let battery: Bool
        let advancedMemory: Bool
        let systemInfo: Bool
        let topCPU: Bool
        let topGPU: Bool
        let topMemory: Bool
    }
    
    init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let numer = Double(max(timebase.numer, 1))
        let denom = Double(max(timebase.denom, 1))
        self.ticksToNanoseconds = numer / denom
        
        self.gpuServices = Self.discoverServices(matching: "IOAccelerator")
        self.batteryServices = Self.discoverServices(matching: "AppleSmartBattery")
    }
    
    deinit {
        for service in gpuServices {
            IOObjectRelease(service)
        }
        for service in batteryServices {
            IOObjectRelease(service)
        }
    }
    
    private nonisolated static func discoverServices(matching serviceName: String) -> [io_registry_entry_t] {
        var services: [io_registry_entry_t] = []
        var matchIterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceName), &matchIterator) == kIOReturnSuccess {
            var service: io_registry_entry_t = IOIteratorNext(matchIterator)
            while service != 0 {
                services.append(service)
                service = IOIteratorNext(matchIterator)
            }
            IOObjectRelease(matchIterator)
        }
        return services
    }
    
    func fetchStats(interval: Double, options: FetchOptions, totalMemory: Double) -> SystemStats {
        let now = Date()
        let realInterval = max(now.timeIntervalSince(self.lastUpdateTime), 0.1)
        self.lastUpdateTime = now
        
        var cpu: (cores: [Double], user: Double, system: Double) = ([], 0, 0)
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
        var topGPU: [TopProcess] = []
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
        if options.topGPU {
            topGPU = self.fetchTopGPU(interval: realInterval)
        }
        
        return SystemStats(
            cpuLoadPerCore: cpu.cores,
            cpuUserLoad: cpu.user,
            cpuSystemLoad: cpu.system,
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
            topGPU: topGPU,
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
    
    private func fetchCPU() -> (cores: [Double], user: Double, system: Double) {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        let hostPort = mach_host_self()
        defer {
            mach_port_deallocate(mach_task_self_, hostPort)
        }
        let result = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else { return ([], 0, 0) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        
        let numCPUs = Int(numCPUsU)
        var currentLoad: [Double] = []
        currentLoad.reserveCapacity(numCPUs)
        var newTicks: [processor_cpu_load_info] = []
        newTicks.reserveCapacity(numCPUs)
        
        var sumUserDiff: Double = 0
        var sumSystemDiff: Double = 0
        var sumTotalDiff: Double = 0
        
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
                let userDiff = Double(user >= prev.cpu_ticks.0 ? user - prev.cpu_ticks.0 : 0)
                let sysDiff = Double(system >= prev.cpu_ticks.1 ? system - prev.cpu_ticks.1 : 0)
                let idleDiff = Double(idle >= prev.cpu_ticks.2 ? idle - prev.cpu_ticks.2 : 0)
                let niceDiff = Double(nice >= prev.cpu_ticks.3 ? nice - prev.cpu_ticks.3 : 0)
                
                let totalDiff = userDiff + sysDiff + idleDiff + niceDiff
                let activeDiff = userDiff + sysDiff + niceDiff
                let load: Double = totalDiff > 0.0 ? min(max(activeDiff / totalDiff, 0.0), 1.0) : 0.0
                currentLoad.append(load)
                
                sumUserDiff += (userDiff + niceDiff)
                sumSystemDiff += sysDiff
                sumTotalDiff += totalDiff
            } else {
                currentLoad.append(0.0)
            }
        }
        self.previousCPUTicks = newTicks
        
        let userLoad = sumTotalDiff > 0.0 ? min(max(sumUserDiff / sumTotalDiff, 0.0), 1.0) : 0.0
        let systemLoad = sumTotalDiff > 0.0 ? min(max(sumSystemDiff / sumTotalDiff, 0.0), 1.0) : 0.0
        return (currentLoad, userLoad, systemLoad)
    }
    
    private func fetchMemory(totalMemory: Double) -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        defer {
            mach_port_deallocate(mach_task_self_, hostPort)
        }
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let pageSize = Double(vm_kernel_page_size)
            let appPages = stats.internal_page_count >= stats.purgeable_count
                ? (stats.internal_page_count - stats.purgeable_count)
                : stats.active_count
            let appMem = Double(appPages) * pageSize
            let wire = Double(stats.wire_count) * pageSize
            let compressed = Double(stats.compressor_page_count) * pageSize
            return min(max(appMem + wire + compressed, 0), totalMemory)
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
        if hasPreviousDiskData {
            readRate = Double(totalRead >= previousDiskBytesRead ? totalRead - previousDiskBytesRead : 0) / interval
            writeRate = Double(totalWrite >= previousDiskBytesWritten ? totalWrite - previousDiskBytesWritten : 0) / interval
        } else {
            hasPreviousDiskData = true
        }
        self.previousDiskBytesRead = totalRead
        self.previousDiskBytesWritten = totalWrite
        return (readRate, writeRate)
    }
    
    private func fetchNetwork64(interval: Double) -> (up: Double, down: Double) {
        var mib = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        if sysctl(&mib, 6, nil, &len, nil, 0) < 0 || len <= 0 {
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
            let headerSize = MemoryLayout<if_msghdr2>.size
            while offset + headerSize <= len {
                let rawPtr = UnsafeRawPointer(baseAddress).advanced(by: offset)
                let ifm = rawPtr.load(as: if_msghdr2.self)
                let msgLen = Int(ifm.ifm_msglen)
                guard msgLen >= headerSize else { break }
                
                if ifm.ifm_type == UInt8(RTM_IFINFO2) {
                    let flags = Int32(ifm.ifm_flags)
                    if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                        bytesIn += ifm.ifm_data.ifi_ibytes
                        bytesOut += ifm.ifm_data.ifi_obytes
                    }
                }
                offset += msgLen
            }
        }
        
        var up: Double = 0
        var down: Double = 0
        if hasPreviousNetworkData {
            down = Double(bytesIn >= previousNetworkBytesIn ? bytesIn - previousNetworkBytesIn : 0) / interval
            up = Double(bytesOut >= previousNetworkBytesOut ? bytesOut - previousNetworkBytesOut : 0) / interval
        } else {
            hasPreviousNetworkData = true
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
            guard (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
                  let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ptr.pointee.ifa_data else { continue }
            let networkData = data.assumingMemoryBound(to: if_data.self).pointee
            bytesIn += UInt64(networkData.ifi_ibytes)
            bytesOut += UInt64(networkData.ifi_obytes)
        }
        var up: Double = 0
        var down: Double = 0
        if hasPreviousNetworkData {
            down = Double(bytesIn >= previousNetworkBytesIn ? bytesIn - previousNetworkBytesIn : 0) / interval
            up = Double(bytesOut >= previousNetworkBytesOut ? bytesOut - previousNetworkBytesOut : 0) / interval
        } else {
            hasPreviousNetworkData = true
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
        
        for batteryService in batteryServices {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(batteryService, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                
                let batteryData = dict["BatteryData"] as? [String: Any]
                
                let maxCap = (dict["MaxCapacity"] as? NSNumber)?.doubleValue ??
                             (batteryData?["MaxCapacity"] as? NSNumber)?.doubleValue ?? 100.0
                let curCap = (dict["CurrentCapacity"] as? NSNumber)?.doubleValue ??
                             (batteryData?["CurrentCapacity"] as? NSNumber)?.doubleValue ?? 0.0
                level = maxCap > 0 ? curCap / maxCap : 0.0
                
                isCharging = dict["IsCharging"] as? Bool ?? false
                if !isCharging {
                    if let isChargingNum = dict["IsCharging"] as? NSNumber {
                        isCharging = isChargingNum.boolValue
                    }
                }
                
                cycles = (dict["CycleCount"] as? NSNumber)?.intValue ??
                         (batteryData?["CycleCount"] as? NSNumber)?.intValue ?? 0
                
                var designCap = (dict["DesignCapacity"] as? NSNumber)?.doubleValue ?? 0.0
                var rawMaxCap = (dict["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue ?? 0.0
                
                if let batteryData = dict["BatteryData"] as? [String: Any] {
                    if designCap == 0 {
                        designCap = (batteryData["DesignCapacity"] as? NSNumber)?.doubleValue ?? 0.0
                    }
                    if rawMaxCap == 0 {
                        rawMaxCap = (batteryData["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue ??
                                    (batteryData["NominalChargeCapacity"] as? NSNumber)?.doubleValue ??
                                    (batteryData["FullChargeCapacity"] as? NSNumber)?.doubleValue ??
                                    (batteryData["MaxCapacity"] as? NSNumber)?.doubleValue ?? 0.0
                    }
                }
                
                if rawMaxCap == 0 {
                    rawMaxCap = maxCap
                }
                if designCap > 0 {
                    if rawMaxCap <= 100 && designCap > 100 {
                        health = 1.0
                    } else {
                        health = min(rawMaxCap / designCap, 1.0)
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
        }
        
        return (level, isCharging, usage, adapterWattage, cycles, health, temperature)
    }
    
    private func fetchGPU() -> Double {
        if gpuServices.isEmpty {
            gpuServices = Self.discoverServices(matching: "IOAccelerator")
        }
        for service in gpuServices {
            if let perfStats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                if let utilization = (perfStats["Device Utilization %"] as? NSNumber) ?? (perfStats["Device Utilization"] as? NSNumber) {
                    return utilization.doubleValue / 100.0
                }
            }
        }
        return 0
    }
    
    private func fetchTopGPU(interval: Double) -> [TopProcess] {
        if gpuServices.isEmpty {
            gpuServices = Self.discoverServices(matching: "IOAccelerator")
        }
        guard !gpuServices.isEmpty else { return [] }
        
        var currentGPUTimes: [Int32: UInt64] = [:]
        var processNames: [Int32: String] = [:]
        
        for service in gpuServices {
            var childIterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIterator) == kIOReturnSuccess {
                var child = IOIteratorNext(childIterator)
                while child != 0 {
                    var props: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(child, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                       let dict = props?.takeRetainedValue() as? [String: Any] {
                        if let creator = dict["IOUserClientCreator"] as? String {
                            let components = creator.components(separatedBy: ",")
                            if components.count >= 1 {
                                let pidString = components[0].replacingOccurrences(of: "pid ", with: "").trimmingCharacters(in: .whitespaces)
                                if let pid = Int32(pidString) {
                                    var name = ""
                                    if components.count >= 2 {
                                        name = components[1].trimmingCharacters(in: .whitespaces)
                                    }
                                    if name.isEmpty {
                                        name = getName(pid: pid)
                                    }
                                    processNames[pid] = name
                                    
                                    var clientGPUTime: UInt64 = 0
                                    if let appUsage = dict["AppUsage"] as? [[String: Any]] {
                                        for entry in appUsage {
                                            if let gpuTime = (entry["accumulatedGPUTime"] as? NSNumber)?.uint64Value {
                                                clientGPUTime += gpuTime
                                            }
                                        }
                                    }
                                    currentGPUTimes[pid, default: 0] += clientGPUTime
                                }
                            }
                        }
                    }
                    IOObjectRelease(child)
                    child = IOIteratorNext(childIterator)
                }
                IOObjectRelease(childIterator)
            }
        }
        
        var candidates: [ProcessCandidate] = []
        let previousTimes = self.previousProcessGPUTimes
        
        for (pid, currentTime) in currentGPUTimes {
            if let prevTime = previousTimes[pid], interval > 0 {
                let delta = Double(currentTime >= prevTime ? currentTime - prevTime : 0)
                let percentage = (delta / 1_000_000_000.0) / interval * 100.0
                if percentage > 0.1 {
                    candidates.append(ProcessCandidate(pid: pid, sortValue: percentage))
                }
            }
        }
        
        self.previousProcessGPUTimes = currentGPUTimes
        
        let topGPUCandidates = candidates.sorted { $0.sortValue > $1.sortValue }.prefix(3)
        return topGPUCandidates.map { item in
            let name = processNames[item.pid] ?? getName(pid: item.pid)
            return TopProcess(pid: item.pid, name: name, value: String(format: "%.1f%%", item.sortValue), sortValue: item.sortValue)
        }
    }
    
    private func fetchTopProcesses(interval: Double, showCPU: Bool, showMemory: Bool) -> (cpu: [TopProcess], memory: [TopProcess]) {
        let pids = getPIDs()
        let count = pids.count
        var cpuCandidates: [ProcessCandidate] = []
        var memCandidates: [ProcessCandidate] = []
        cpuCandidates.reserveCapacity(32)
        memCandidates.reserveCapacity(count)
        var currentTimes: [Int32: UInt64] = [:]
        currentTimes.reserveCapacity(count)
        
        // Prune name cache and CPU/GPU times for dead processes periodically
        pruningCounter += 1
        if pruningCounter >= 10 {
            let currentPidsSet = Set(pids)
            nameCache = nameCache.filter { currentPidsSet.contains($0.key) }
            previousProcessCPUTimes = previousProcessCPUTimes.filter { currentPidsSet.contains($0.key) }
            previousProcessGPUTimes = previousProcessGPUTimes.filter { currentPidsSet.contains($0.key) }
            pruningCounter = 0
        }
        
        let previousTimes = self.previousProcessCPUTimes
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        var usage = proc_taskinfo()
        
        for pid in pids {
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &usage, size) == size {
                if showCPU {
                    let totalTicks = usage.pti_total_user + usage.pti_total_system
                    currentTimes[pid] = totalTicks
                    if let prevTicks = previousTimes[pid], interval > 0 {
                        let deltaTicks = Double(totalTicks >= prevTicks ? totalTicks - prevTicks : 0)
                        let deltaNs = deltaTicks * ticksToNanoseconds
                        let percentage = (deltaNs / 1_000_000_000.0) / interval * 100.0
                        if percentage > 0.1 {
                            cpuCandidates.append(ProcessCandidate(pid: pid, sortValue: percentage))
                        }
                    }
                }
                
                if showMemory {
                    let residentSize = Double(usage.pti_resident_size)
                    if residentSize > 0 {
                        memCandidates.append(ProcessCandidate(pid: pid, sortValue: residentSize))
                    }
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
            cpu: topCPUCandidates.map { TopProcess(pid: $0.pid, name: resolveName($0.pid), value: String(format: "%.1f%%", $0.sortValue), sortValue: $0.sortValue) },
            memory: topMemCandidates.map { item -> TopProcess in
                let mb = item.sortValue / 1_048_576.0
                let displayValue = mb >= 1024 ? String(format: "%.1f GB", mb / 1024.0) : String(format: "%.0f MB", mb)
                return TopProcess(pid: item.pid, name: resolveName(item.pid), value: displayValue, sortValue: item.sortValue)
            }
        )
    }
    
    private func getPIDs() -> [Int32] {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        let count = Int(bufferSize) / MemoryLayout<Int32>.size + 32
        var pids = [Int32](repeating: 0, count: count)
        let actualBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(count * MemoryLayout<Int32>.size))
        if actualBytes <= 0 { return [] }
        let actualCount = Int(actualBytes) / MemoryLayout<Int32>.size
        return pids.prefix(actualCount).filter { $0 > 0 }
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
