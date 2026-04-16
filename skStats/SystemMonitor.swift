import Foundation
import Combine
import Darwin

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
        
        if UserDefaults.standard.object(forKey: "updateInterval") != nil {
            updateInterval = UserDefaults.standard.double(forKey: "updateInterval")
        }
        
        // Defaults if not set
        if UserDefaults.standard.object(forKey: "showCPU") == nil {
            showCPU = true; showGPU = true; showMemory = true; showDisk = true; showNetwork = true
        }
    }
    
    func saveSettings() {
        UserDefaults.standard.set(showCPU, forKey: "showCPU")
        UserDefaults.standard.set(showGPU, forKey: "showGPU")
        UserDefaults.standard.set(showMemory, forKey: "showMemory")
        UserDefaults.standard.set(showDisk, forKey: "showDisk")
        UserDefaults.standard.set(showNetwork, forKey: "showNetwork")
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
        if showDisk { updateDisk() } // Stubbed or simplified due to IOKit bridging constraints
        if showNetwork { updateNetwork() }
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
                    
                    let load: Double = totalDiff > 0.0 ? (activeDiff / totalDiff) : 0.0
                    currentLoad.append(load)
                } else {
                    currentLoad.append(0.0)
                }
            }
            
            self.cpuLoadPerCore = currentLoad
            self.previousCPUTicks = newTicks
            
            let vmPageSize = vm_page_size
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
            self.memoryUsed = active + wire + compressed
        }
    }
    
    private func updateDisk() {
        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
            process.arguments = ["-c", "IOBlockStorageDriver", "-r", "-w", "0"]
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    var totalRead: UInt64 = 0
                    var totalWrite: UInt64 = 0
                    
                    do {
                        let readRegex = try NSRegularExpression(pattern: "\"Bytes \\(Read\\)\"=(\\d+)")
                        let writeRegex = try NSRegularExpression(pattern: "\"Bytes \\(Write\\)\"=(\\d+)")
                        let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
                        
                        let readMatches = readRegex.matches(in: output, range: nsRange)
                        for match in readMatches {
                            if let r = Range(match.range(at: 1), in: output), let val = UInt64(output[r]) {
                                totalRead += val
                            }
                        }
                        
                        let writeMatches = writeRegex.matches(in: output, range: nsRange)
                        for match in writeMatches {
                            if let r = Range(match.range(at: 1), in: output), let val = UInt64(output[r]) {
                                totalWrite += val
                            }
                        }
                    } catch {
                        print("Regex error")
                    }
                    
                    if totalRead > 0 && totalWrite > 0 {
                        let readRate = self.previousDiskBytesRead > 0 ? (totalRead - self.previousDiskBytesRead) : 0
                        let writeRate = self.previousDiskBytesWritten > 0 ? (totalWrite - self.previousDiskBytesWritten) : 0
                        
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.diskReadRate = Double(readRate) / self.updateInterval
                            self.diskWriteRate = Double(writeRate) / self.updateInterval
                        }
                        
                        self.previousDiskBytesRead = totalRead
                        self.previousDiskBytesWritten = totalWrite
                    }
                }
            } catch {
                print("Failed to get Disk stats")
            }
        }
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
            self.networkDownloadRate = Double(bytesIn - previousNetworkBytesIn) / updateInterval
            self.networkUploadRate = Double(bytesOut - previousNetworkBytesOut) / updateInterval
        }
        
        self.previousNetworkBytesIn = bytesIn
        self.previousNetworkBytesOut = bytesOut
    }
    
    private func updateGPU() {
        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
            process.arguments = ["-l", "-w", "0"]
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    if let range = output.range(of: "\"Device Utilization %\"=") {
                        let substring = output[range.upperBound...]
                        if let endRange = substring.range(of: ",") {
                            if let load = Double(substring[..<endRange.lowerBound]) {
                                DispatchQueue.main.async { self.gpuLoad = load / 100.0 }
                            }
                        } else if let endRange2 = substring.range(of: "}") {
                            if let load = Double(substring[..<endRange2.lowerBound]) {
                                DispatchQueue.main.async { self.gpuLoad = load / 100.0 }
                            }
                        }
                    }
                }
            } catch {
                print("Failed to get GPU usage")
            }
        }
    }
}
