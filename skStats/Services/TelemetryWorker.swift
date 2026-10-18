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
    private var currentGPUTimesBuffer: [Int32: UInt64] = [:]
    private var nameCache: [Int32: String] = [:]
    private var pidBuffer: [Int32] = []
    private var netBuffer: [UInt8] = []
    private var cachedDiskSpace: (free: Int64, total: Int64) = (0, 0)
    private var diskSpaceTickCounter: Int = 0
    private var lastUpdateTime: Date = Date()
    private var pruningCounter: Int = 0
    
    private let hostPort: mach_port_t
    private let pidListType: UInt32
    private let pidListInfo: UInt32
    private var gpuServices: [io_registry_entry_t]
    private var batteryServices: [io_registry_entry_t]
    private var diskServices: [io_registry_entry_t]
    private let ticksToNanoseconds: Double
    
    private struct ProcessCandidate {
        let pid: Int32
        let sortValue: Double
    }
    
    /// Fixed-capacity stack tracker for the top 3 processes in O(N) time with zero heap allocations during iteration.
    private struct Top3Tracker {
        private var first = ProcessCandidate(pid: 0, sortValue: -1)
        private var second = ProcessCandidate(pid: 0, sortValue: -1)
        private var third = ProcessCandidate(pid: 0, sortValue: -1)
        
        mutating func insert(pid: Int32, value: Double) {
            guard value > third.sortValue else { return }
            let candidate = ProcessCandidate(pid: pid, sortValue: value)
            if value > first.sortValue {
                third = second
                second = first
                first = candidate
            } else if value > second.sortValue {
                third = second
                second = candidate
            } else {
                third = candidate
            }
        }
        
        func mapResults(_ transform: (ProcessCandidate) -> TopProcess) -> [TopProcess] {
            var res: [TopProcess] = []
            res.reserveCapacity(3)
            if first.pid > 0 { res.append(transform(first)) }
            if second.pid > 0 { res.append(transform(second)) }
            if third.pid > 0 { res.append(transform(third)) }
            return res
        }
    }
    
    struct FetchOptions: Sendable {
        let cpu: Bool
        let perCoreCPU: Bool
        let gpu: Bool
        let memory: Bool
        let disk: Bool
        let network: Bool
        let battery: Bool
        let detailedBattery: Bool
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
        self.hostPort = mach_host_self()
        
        let uid = getuid()
        self.pidListType = uid == 0 ? UInt32(PROC_ALL_PIDS) : UInt32(PROC_UID_ONLY)
        self.pidListInfo = uid == 0 ? 0 : uid
        self.pidBuffer = [Int32](repeating: 0, count: 1024)
        
        self.gpuServices = Self.discoverServices(matching: "IOAccelerator")
        self.batteryServices = Self.discoverServices(matching: "AppleSmartBattery")
        self.diskServices = Self.discoverServices(matching: "IOBlockStorageDriver")
    }
    
    deinit {
        if hostPort != MACH_PORT_NULL {
            mach_port_deallocate(mach_task_self_, hostPort)
        }
        for service in gpuServices {
            IOObjectRelease(service)
        }
        for service in batteryServices {
            IOObjectRelease(service)
        }
        for service in diskServices {
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
    
    @inline(__always)
    private func quantizeRatio(_ value: Double) -> Double {
        (min(max(value, 0.0), 1.0) * 1000.0).rounded() / 1000.0
    }
    
    func fetchStats(interval: Double, options: FetchOptions, totalMemory: Double) -> SystemStats {
        let now = Date()
        let realInterval = max(now.timeIntervalSince(self.lastUpdateTime), 0.1)
        self.lastUpdateTime = now
        
        var cpu: (cores: [Double], user: Double, system: Double, total: Double) = ([], 0, 0, 0)
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
        
        if options.cpu { cpu = self.fetchCPU(includePerCore: options.perCoreCPU) }
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
        if options.battery { battery = self.fetchBattery(detailed: options.detailedBattery) }
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
            totalCPULoad: cpu.total,
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
        if cachedDiskSpace.total > 0 && diskSpaceTickCounter < 10 {
            diskSpaceTickCounter += 1
            return cachedDiskSpace
        }
        diskSpaceTickCounter = 0
        var fs = statfs()
        if statfs("/", &fs) == 0 {
            let blockSize = Int64(fs.f_bsize)
            let free = Int64(fs.f_bavail) * blockSize
            let total = Int64(fs.f_blocks) * blockSize
            cachedDiskSpace = (free, total)
            return cachedDiskSpace
        }
        return cachedDiskSpace
    }
    
    private func fetchUptime() -> TimeInterval {
        // FormatUtils.formatUptime displays up to minute granularity; quantizing to 60s avoids redundant view updates every tick.
        return floor(ProcessInfo.processInfo.systemUptime / 60.0) * 60.0
    }
    
    private func fetchCPU(includePerCore: Bool) -> (cores: [Double], user: Double, system: Double, total: Double) {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        let result = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else { return ([], 0, 0, 0) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        
        let numCPUs = Int(numCPUsU)
        let hasPrev = (previousCPUTicks.count == numCPUs)
        if !hasPrev {
            previousCPUTicks = [processor_cpu_load_info](
                repeating: processor_cpu_load_info(cpu_ticks: (0, 0, 0, 0)),
                count: numCPUs
            )
        }
        
        var currentLoad: [Double] = []
        if includePerCore {
            currentLoad.reserveCapacity(numCPUs)
        }
        
        var sumUserDiff: Double = 0
        var sumSystemDiff: Double = 0
        var sumTotalDiff: Double = 0
        
        for i in 0..<numCPUs {
            let offset = i * Int(CPU_STATE_MAX)
            let user = UInt32(cpuInfo[offset + Int(CPU_STATE_USER)])
            let system = UInt32(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt32(cpuInfo[offset + Int(CPU_STATE_NICE)])
            
            if hasPrev {
                let prev = previousCPUTicks[i]
                let userDiff = Double(user >= prev.cpu_ticks.0 ? user - prev.cpu_ticks.0 : 0)
                let sysDiff = Double(system >= prev.cpu_ticks.1 ? system - prev.cpu_ticks.1 : 0)
                let idleDiff = Double(idle >= prev.cpu_ticks.2 ? idle - prev.cpu_ticks.2 : 0)
                let niceDiff = Double(nice >= prev.cpu_ticks.3 ? nice - prev.cpu_ticks.3 : 0)
                
                let totalDiff = userDiff + sysDiff + idleDiff + niceDiff
                if includePerCore {
                    let activeDiff = userDiff + sysDiff + niceDiff
                    let load: Double = totalDiff > 0.0 ? quantizeRatio(activeDiff / totalDiff) : 0.0
                    currentLoad.append(load)
                }
                
                sumUserDiff += (userDiff + niceDiff)
                sumSystemDiff += sysDiff
                sumTotalDiff += totalDiff
            } else if includePerCore {
                currentLoad.append(0.0)
            }
            
            previousCPUTicks[i] = processor_cpu_load_info(cpu_ticks: (user, system, idle, nice))
        }
        
        let userLoad = sumTotalDiff > 0.0 ? quantizeRatio(sumUserDiff / sumTotalDiff) : 0.0
        let systemLoad = sumTotalDiff > 0.0 ? quantizeRatio(sumSystemDiff / sumTotalDiff) : 0.0
        let totalLoad = sumTotalDiff > 0.0 ? quantizeRatio((sumUserDiff + sumSystemDiff) / sumTotalDiff) : 0.0
        return (currentLoad, userLoad, systemLoad, totalLoad)
    }
    
    private func fetchMemory(totalMemory: Double) -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
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
        if diskServices.isEmpty {
            diskServices = Self.discoverServices(matching: "IOBlockStorageDriver")
        }
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        for drive in diskServices {
            if let stats = IORegistryEntryCreateCFProperty(drive, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSDictionary {
                if let readBytes = stats["Bytes (Read)"] as? NSNumber { totalRead &+= readBytes.uint64Value }
                if let writeBytes = stats["Bytes (Write)"] as? NSNumber { totalWrite &+= writeBytes.uint64Value }
            }
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
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        if sysctl(&mib, 6, nil, &len, nil, 0) < 0 || len <= 0 {
            return (0, 0)
        }
        
        let requiredCapacity = len + 1024
        if netBuffer.count < requiredCapacity {
            netBuffer = [UInt8](repeating: 0, count: requiredCapacity)
        }
        
        var actualLen = netBuffer.count
        let sysctlResult = netBuffer.withUnsafeMutableBytes { rawBuf -> Int32 in
            guard let baseAddress = rawBuf.baseAddress else { return -1 }
            return sysctl(&mib, 6, baseAddress, &actualLen, nil, 0)
        }
        if sysctlResult < 0 || actualLen <= 0 {
            return (0, 0)
        }
        
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        
        let baseHeaderSize = 4 // ifm_msglen (UInt16), ifm_version (UInt8), ifm_type (UInt8)
        let ifInfoSize = MemoryLayout<if_msghdr2>.size
        
        netBuffer.withUnsafeBytes { rawBuf in
            var offset = 0
            while offset + baseHeaderSize <= actualLen {
                let msgLen = Int(rawBuf.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard msgLen >= baseHeaderSize, offset + msgLen <= actualLen else { break }
                
                let msgType = rawBuf.loadUnaligned(fromByteOffset: offset + 3, as: UInt8.self)
                if msgType == UInt8(RTM_IFINFO2), msgLen >= ifInfoSize {
                    let ifm = rawBuf.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let flags = Int32(ifm.ifm_flags)
                    if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                        bytesIn &+= ifm.ifm_data.ifi_ibytes
                        bytesOut &+= ifm.ifm_data.ifi_obytes
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
    
    private func fetchBattery(detailed: Bool) -> (level: Double, isCharging: Bool, usage: Double, adapter: Int, cycles: Int, health: Double, temperature: Double) {
        var level: Double = 0
        var isCharging: Bool = false
        var cycles: Int = 0
        var health: Double = 0
        var usage: Double = 0
        var adapterWattage: Int = 0
        var temperature: Double = 0.0
        
        for batteryService in batteryServices {
            if !detailed {
                // Fast path for Menu Bar when popover is closed: fetch only 3 scalar properties without copying the 60+ key registry dictionary.
                let maxCap = (IORegistryEntryCreateCFProperty(batteryService, "MaxCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.doubleValue ?? 100.0
                let curCap = (IORegistryEntryCreateCFProperty(batteryService, "CurrentCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.doubleValue ?? 0.0
                level = maxCap > 0 ? quantizeRatio(curCap / maxCap) : 0.0
                if let chargingNum = IORegistryEntryCreateCFProperty(batteryService, "IsCharging" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                    isCharging = chargingNum.boolValue
                }
                continue
            }
            
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(batteryService, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as NSDictionary? {
                
                let batteryData = dict["BatteryData"] as? NSDictionary
                
                let maxCap = (dict["MaxCapacity"] as? NSNumber)?.doubleValue ??
                             (batteryData?["MaxCapacity"] as? NSNumber)?.doubleValue ?? 100.0
                let curCap = (dict["CurrentCapacity"] as? NSNumber)?.doubleValue ??
                             (batteryData?["CurrentCapacity"] as? NSNumber)?.doubleValue ?? 0.0
                level = maxCap > 0 ? quantizeRatio(curCap / maxCap) : 0.0
                
                if let isChargingNum = dict["IsCharging"] as? NSNumber {
                    isCharging = isChargingNum.boolValue
                }
                
                cycles = (dict["CycleCount"] as? NSNumber)?.intValue ??
                         (batteryData?["CycleCount"] as? NSNumber)?.intValue ?? 0
                
                var designCap = (dict["DesignCapacity"] as? NSNumber)?.doubleValue ?? 0.0
                var rawMaxCap = (dict["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue ?? 0.0
                
                if let batteryData = batteryData {
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
                        health = quantizeRatio(rawMaxCap / designCap)
                    }
                }
                
                if let amperage = (dict["Amperage"] as? NSNumber)?.int64Value,
                   let voltage = (dict["Voltage"] as? NSNumber)?.int64Value {
                    usage = Double(amperage) * Double(voltage) / 1_000_000.0 // mA * mV = uW -> W
                }
                
                if let adapterDetails = dict["AdapterDetails"] as? NSDictionary,
                   let watts = (adapterDetails["Watts"] as? NSNumber)?.intValue {
                    adapterWattage = watts
                }
                
                if let tempRaw = (dict["Temperature"] as? NSNumber)?.doubleValue {
                    temperature = (tempRaw / 10.0).rounded() / 10.0 // centi-Celsius rounded to 0.1°C
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
            if let perfStats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSDictionary {
                if let utilization = (perfStats["Device Utilization %"] as? NSNumber) ?? (perfStats["Device Utilization"] as? NSNumber) {
                    return quantizeRatio(utilization.doubleValue / 100.0)
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
        
        currentGPUTimesBuffer.removeAll(keepingCapacity: true)
        
        for service in gpuServices {
            var childIterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIterator) == kIOReturnSuccess {
                var child = IOIteratorNext(childIterator)
                while child != 0 {
                    if let appUsage = IORegistryEntryCreateCFProperty(child, "AppUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSArray {
                        var clientGPUTime: UInt64 = 0
                        for entry in appUsage {
                            if let entryDict = entry as? NSDictionary,
                               let gpuTime = (entryDict["accumulatedGPUTime"] as? NSNumber)?.uint64Value {
                                clientGPUTime &+= gpuTime
                            }
                        }
                        if clientGPUTime > 0,
                           let creator = IORegistryEntryCreateCFProperty(child, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                           let pid = Self.parseCreatorPID(creator) {
                            currentGPUTimesBuffer[pid, default: 0] &+= clientGPUTime
                            if nameCache[pid] == nil, let extractedName = Self.parseCreatorName(creator) {
                                nameCache[pid] = extractedName
                            }
                        }
                    }
                    IOObjectRelease(child)
                    child = IOIteratorNext(childIterator)
                }
                IOObjectRelease(childIterator)
            }
        }
        
        var topGPUTracker = Top3Tracker()
        let previousTimes = self.previousProcessGPUTimes
        
        for (pid, currentTime) in currentGPUTimesBuffer {
            if let prevTime = previousTimes[pid], interval > 0 {
                let delta = Double(currentTime >= prevTime ? currentTime - prevTime : 0)
                let percentage = (delta / 1_000_000_000.0) / interval * 100.0
                if percentage > 0.1 {
                    topGPUTracker.insert(pid: pid, value: percentage)
                }
            }
        }
        
        swap(&self.previousProcessGPUTimes, &self.currentGPUTimesBuffer)
        
        return topGPUTracker.mapResults { item in
            let name = resolveName(item.pid)
            return TopProcess(pid: item.pid, name: name, value: String(format: "%.1f%%", item.sortValue), sortValue: item.sortValue)
        }
    }
    
    /// Zero-allocation parser for `"pid 1234, ProcessName"`
    private nonisolated static func parseCreatorPID(_ creator: String) -> Int32? {
        var utf8 = creator.utf8[...]
        if utf8.starts(with: "pid ".utf8) {
            utf8 = utf8.dropFirst(4)
        }
        var pid: Int32 = 0
        var hasDigits = false
        for byte in utf8 {
            if byte >= 48 && byte <= 57 {
                pid = pid &* 10 &+ Int32(byte - 48)
                hasDigits = true
            } else if byte == 32 && !hasDigits {
                continue
            } else {
                break
            }
        }
        return hasDigits && pid > 0 ? pid : nil
    }
    
    private nonisolated static func parseCreatorName(_ creator: String) -> String? {
        guard let commaIndex = creator.firstIndex(of: ",") else { return nil }
        let nameSlice = creator[creator.index(after: commaIndex)...].drop(while: { $0 == " " })
        return nameSlice.isEmpty ? nil : String(nameSlice)
    }
    
    private func fetchTopProcesses(interval: Double, showCPU: Bool, showMemory: Bool) -> (cpu: [TopProcess], memory: [TopProcess]) {
        let actualCount = populatePIDBuffer()
        guard actualCount > 0 else { return ([], []) }
        
        var topCPUTracker = Top3Tracker()
        var topMemTracker = Top3Tracker()
        
        // Prune name cache and CPU/GPU times for dead processes periodically
        pruningCounter += 1
        if pruningCounter >= 10 {
            var currentPidsSet = Set<Int32>(minimumCapacity: actualCount)
            for i in 0..<actualCount {
                let pid = pidBuffer[i]
                if pid > 0 { currentPidsSet.insert(pid) }
            }
            nameCache = nameCache.filter { currentPidsSet.contains($0.key) }
            previousProcessCPUTimes = previousProcessCPUTimes.filter { currentPidsSet.contains($0.key) }
            previousProcessGPUTimes = previousProcessGPUTimes.filter { currentPidsSet.contains($0.key) }
            pruningCounter = 0
        }
        
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        var usage = proc_taskinfo()
        
        for i in 0..<actualCount {
            let pid = pidBuffer[i]
            guard pid > 0 else { continue }
            
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &usage, size) == size {
                if showCPU {
                    let totalTicks = usage.pti_total_user &+ usage.pti_total_system
                    let prevTicks = previousProcessCPUTimes.updateValue(totalTicks, forKey: pid)
                    if let prevTicks = prevTicks, interval > 0 {
                        let deltaTicks = Double(totalTicks >= prevTicks ? totalTicks - prevTicks : 0)
                        if deltaTicks > 0 {
                            let deltaNs = deltaTicks * ticksToNanoseconds
                            let percentage = (deltaNs / 1_000_000_000.0) / interval * 100.0
                            if percentage > 0.1 {
                                topCPUTracker.insert(pid: pid, value: percentage)
                            }
                        }
                    }
                }
                
                if showMemory {
                    let residentSize = Double(usage.pti_resident_size)
                    if residentSize > 0 {
                        topMemTracker.insert(pid: pid, value: residentSize)
                    }
                }
            }
        }
        
        return (
            cpu: topCPUTracker.mapResults { TopProcess(pid: $0.pid, name: resolveName($0.pid), value: String(format: "%.1f%%", $0.sortValue), sortValue: $0.sortValue) },
            memory: topMemTracker.mapResults { item -> TopProcess in
                let mb = item.sortValue / 1_048_576.0
                let displayValue = mb >= 1024 ? String(format: "%.1f GB", mb / 1024.0) : String(format: "%.0f MB", mb)
                return TopProcess(pid: item.pid, name: resolveName(item.pid), value: displayValue, sortValue: item.sortValue)
            }
        )
    }
    
    private func resolveName(_ pid: Int32) -> String {
        if let cached = nameCache[pid] { return cached }
        let name = getName(pid: pid)
        nameCache[pid] = name
        return name
    }
    
    private func populatePIDBuffer() -> Int {
        let listType = pidListType
        let listInfo = pidListInfo
        let actualBytes = pidBuffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return 0 }
            return proc_listpids(listType, listInfo, base, Int32(ptr.count * MemoryLayout<Int32>.size))
        }
        guard actualBytes > 0 else { return 0 }
        let count = Int(actualBytes) / MemoryLayout<Int32>.size
        if count >= pidBuffer.count - 16 {
            let newCap = max(pidBuffer.count * 2, count + 256)
            pidBuffer = [Int32](repeating: 0, count: newCap)
            let retryBytes = pidBuffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
                guard let base = ptr.baseAddress else { return 0 }
                return proc_listpids(listType, listInfo, base, Int32(ptr.count * MemoryLayout<Int32>.size))
            }
            guard retryBytes > 0 else { return 0 }
            return min(Int(retryBytes) / MemoryLayout<Int32>.size, pidBuffer.count)
        }
        return min(count, pidBuffer.count)
    }
    
    private func getName(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 4)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            return String(cString: buffer)
        }
        return "Unknown"
    }
}

