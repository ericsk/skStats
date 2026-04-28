import Foundation
import Combine
import Darwin
import IOKit
import IOKit.storage
import IOKit.network

struct TopProcess: Identifiable {
    let id = UUID()
    let name: String
    let value: String
}

class SystemMonitor: ObservableObject {
    @Published var cpuLoadPerCore: [Double] = []
    @Published var gpuLoad: Double = 0.0
    @Published var memoryUsed: Double = 0.0
    @Published var memoryTotal: Double = 0.0
    @Published var diskReadRate: Double = 0.0
    @Published var diskWriteRate: Double = 0.0
    @Published var networkUploadRate: Double = 0.0
    @Published var networkDownloadRate: Double = 0.0
    
    // Settings state
    @Published var showCPU: Bool = true
    @Published var showGPU: Bool = true
    @Published var showMemory: Bool = true
    @Published var showDisk: Bool = true
    @Published var showNetwork: Bool = true
    @Published var showTopCPU: Bool = true
    @Published var showTopMemory: Bool = true
    
    @Published var topCPU: [TopProcess] = []
    @Published var topMemory: [TopProcess] = []
    @Published var updateInterval: Double = 5.0
    
    private var timer: AnyCancellable?
    
    private var previousCPUTicks: [processor_cpu_load_info] = []
    private var previousDiskBytesRead: UInt64 = 0
    private var previousDiskBytesWritten: UInt64 = 0
    private var previousNetworkBytesIn: UInt64 = 0
    private var previousNetworkBytesOut: UInt64 = 0
    
    init() {
        self.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        loadSettings()
        startMonitoring()
    }
    
    func loadSettings() {
        showCPU = UserDefaults.standard.bool(forKey: "showCPU")
        showGPU = UserDefaults.standard.bool(forKey: "showGPU")
        showMemory = UserDefaults.standard.bool(forKey: "showMemory")
        showDisk = UserDefaults.standard.bool(forKey: "showDisk")
        showNetwork = UserDefaults.standard.bool(forKey: "showNetwork")
        showTopCPU = UserDefaults.standard.bool(forKey: "showTopCPU")
        showTopMemory = UserDefaults.standard.bool(forKey: "showTopMemory")
        
        if UserDefaults.standard.object(forKey: "updateInterval") != nil {
            updateInterval = UserDefaults.standard.double(forKey: "updateInterval")
        }
        
        // Defaults if not set
        if UserDefaults.standard.object(forKey: "showCPU") == nil {
            showCPU = true; showGPU = true; showMemory = true; showDisk = true; showNetwork = true; showTopCPU = true; showTopMemory = true
        }
    }
    
    func saveSettings() {
        UserDefaults.standard.set(showCPU, forKey: "showCPU")
        UserDefaults.standard.set(showGPU, forKey: "showGPU")
        UserDefaults.standard.set(showMemory, forKey: "showMemory")
        UserDefaults.standard.set(showDisk, forKey: "showDisk")
        UserDefaults.standard.set(showNetwork, forKey: "showNetwork")
        UserDefaults.standard.set(showTopCPU, forKey: "showTopCPU")
        UserDefaults.standard.set(showTopMemory, forKey: "showTopMemory")
        UserDefaults.standard.set(updateInterval, forKey: "updateInterval")
    }
    
    func startMonitoring() {
        timer?.cancel()
        self.updateStats()
        timer = Timer.publish(every: updateInterval, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.updateStats()
        }
    }
    
    func updateStats() {
        if showCPU { updateCPU() }
        if showGPU { updateGPU() }
        if showMemory { updateMemory() }
        if showDisk { updateDisk() }
        if showNetwork { updateNetwork() }
        if showTopCPU { updateTopCPUProcesses() }
        if showTopMemory { updateTopMemoryProcesses() }
    }
    
    private func updateCPU() {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        
        if result == KERN_SUCCESS, let cpuInfo = cpuInfo {
            let infoPointer = cpuInfo.withMemoryRebound(to: integer_t.self, capacity: Int(numCpuInfo)) { $0 }
            let numCPUs = Int(numCPUsU)
            var currentLoad: [Double] = []
            var newTicks: [processor_cpu_load_info] = []
            
            for i in 0..<numCPUs {
                let offset = i * 4 // Equivalent of HOST_CPU_LOAD_INFO_COUNT
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
            
            self.cpuLoadPerCore = currentLoad
            self.previousCPUTicks = newTicks
            
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
    }
    
    private func updateMemory() {
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
            self.memoryUsed = min(active + wire + compressed, self.memoryTotal)
        }
    }
    
    private func updateDisk() {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        
        var matchIterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching("IOBlockStorageDriver")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &matchIterator)
        
        if result == kIOReturnSuccess {
            var drive: io_registry_entry_t = IOIteratorNext(matchIterator)
            while drive != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(drive, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let props = properties?.takeRetainedValue() as? [String: Any],
                   let stats = props["Statistics"] as? [String: Any] {
                    
                    if let readBytes = stats["Bytes (Read)"] as? NSNumber {
                        totalRead += readBytes.uint64Value
                    }
                    if let writeBytes = stats["Bytes (Write)"] as? NSNumber {
                        totalWrite += writeBytes.uint64Value
                    }
                }
                IOObjectRelease(drive)
                drive = IOIteratorNext(matchIterator)
            }
            IOObjectRelease(matchIterator)
        }
        
        if previousDiskBytesRead > 0 {
            let readRate = totalRead >= previousDiskBytesRead ? (totalRead - previousDiskBytesRead) : 0
            let writeRate = totalWrite >= previousDiskBytesWritten ? (totalWrite - previousDiskBytesWritten) : 0
            
            self.diskReadRate = Double(readRate) / updateInterval
            self.diskWriteRate = Double(writeRate) / updateInterval
        }
        
        self.previousDiskBytesRead = totalRead
        self.previousDiskBytesWritten = totalWrite
    }
    
    private func updateNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        guard let firstAddr = ifaddr else { return }
        
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
        freeifaddrs(ifaddr)
        
        if previousNetworkBytesIn > 0 && previousNetworkBytesOut > 0 {
            self.networkDownloadRate = bytesIn >= previousNetworkBytesIn ? Double(bytesIn - previousNetworkBytesIn) / updateInterval : 0
            self.networkUploadRate = bytesOut >= previousNetworkBytesOut ? Double(bytesOut - previousNetworkBytesOut) / updateInterval : 0
        }
        
        self.previousNetworkBytesIn = bytesIn
        self.previousNetworkBytesOut = bytesOut
    }
    
    private func updateGPU() {
        var matchIterator: io_iterator_t = 0
        // On Apple Silicon, look for "AppleARMGPU" or "AGXAccelerator"
        // On Intel, look for "IntelAccelerator" or "IOAccelerator"
        let matchingDict = IOServiceMatching("IOAccelerator")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &matchIterator)
        
        if result == kIOReturnSuccess {
            var service: io_registry_entry_t = IOIteratorNext(matchIterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let props = properties?.takeRetainedValue() as? [String: Any],
                   let perfStats = props["PerformanceStatistics"] as? [String: Any] {
                    
                    if let utilization = perfStats["Device Utilization %"] as? NSNumber {
                        self.gpuLoad = utilization.doubleValue / 100.0
                        IOObjectRelease(service)
                        break // Found the active one
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(matchIterator)
            }
            IOObjectRelease(matchIterator)
        }
    }
    
    private func updateTopCPUProcesses() {
        let pids = getPIDs()
        var processes: [(name: String, cpu: Float)] = []
        
        for pid in pids {
            var usage = proc_taskinfo()
            let size = MemoryLayout<proc_taskinfo>.size
            let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &usage, Int32(size))
            
            if result == Int32(size) {
                let name = getName(pid: pid)
                // 註：這是一個簡化的權重排序
                processes.append((name: name, cpu: Float(usage.pti_total_user + usage.pti_total_system)))
            }
        }
        
        let topList = processes.sorted { $0.cpu > $1.cpu }.prefix(3).map { 
            TopProcess(name: $0.name, value: "Active") 
        }
        
        DispatchQueue.main.async { self.topCPU = topList }
    }
    
    private func updateTopMemoryProcesses() {
        let pids = getPIDs()
        var processes: [(name: String, mem: UInt64)] = []
        
        for pid in pids {
            var usage = proc_taskinfo()
            let size = MemoryLayout<proc_taskinfo>.size
            let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &usage, Int32(size))
            
            if result == Int32(size) {
                let name = getName(pid: pid)
                processes.append((name: name, mem: usage.pti_resident_size))
            }
        }
        
        let topList = processes.sorted { $0.mem > $1.mem }.prefix(3).map { p in
            let mb = Double(p.mem) / 1024.0 / 1024.0
            let formatValue = mb > 1024 ? String(format: "%.1f GB", mb / 1024.0) : String(format: "%.0f MB", mb)
            return TopProcess(name: p.name, value: formatValue)
        }
        
        DispatchQueue.main.async { self.topMemory = topList }
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
        let maxPath = 4096 // PROC_PIDPATHINFO_MAXSIZE
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxPath)
        defer { buffer.deallocate() }
        let result = proc_name(pid, buffer, UInt32(maxPath))
        if result > 0 {
            return String(cString: buffer)
        }
        return "Unknown"
    }
}
