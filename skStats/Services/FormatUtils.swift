import Foundation

struct FormatUtils {
    static func formatBytes(_ bytes: Double) -> String {
        guard !bytes.isNaN && !bytes.isInfinite && bytes > 0 else { return "0 B" }
        if bytes < 1024 { return "\(Int(bytes.rounded())) B" }
        let kb = bytes / 1024.0
        if kb < 1024 { return "\(Int(kb.rounded())) KB" }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024.0
        if gb < 1024 { return String(format: "%.1f GB", gb) }
        let tb = gb / 1024.0
        return String(format: "%.2f TB", tb)
    }
    
    static func formatMemoryGB(_ bytes: Double) -> String {
        guard !bytes.isNaN && !bytes.isInfinite && bytes > 0 else { return "0.0 GB" }
        let gb = bytes / 1_073_741_824.0 // 1024^3
        return String(format: "%.1f GB", gb)
    }
    
    static func formatRate(_ bytesPerSecond: Double) -> String {
        guard !bytesPerSecond.isNaN && !bytesPerSecond.isInfinite && bytesPerSecond > 0 else { return "0.0 KB/s" }
        let kbps = bytesPerSecond / 1024.0
        if kbps < 1024 {
            return String(format: "%.1f KB/s", kbps)
        }
        let mbps = kbps / 1024.0
        if mbps < 1024 {
            return String(format: "%.1f MB/s", mbps)
        }
        let gbps = mbps / 1024.0
        return String(format: "%.2f GB/s", gbps)
    }
    
    @inline(__always)
    static func formatPercentage(_ value: Double) -> String {
        guard !value.isNaN && !value.isInfinite else { return "0%" }
        let pct = Int((max(value, 0) * 100.0).rounded())
        return "\(pct)%"
    }
    
    @inline(__always)
    static func formatCompactRate(_ bytesPerSecond: Double) -> String {
        guard !bytesPerSecond.isNaN && !bytesPerSecond.isInfinite && bytesPerSecond > 0 else { return "0K" }
        let kbps = bytesPerSecond / 1024.0
        if kbps < 1024 {
            return "\(Int(kbps.rounded()))K"
        }
        let mbps = kbps / 1024.0
        if mbps < 1024 {
            return String(format: "%.1fM", mbps)
        }
        let gbps = mbps / 1024.0
        return String(format: "%.1fG", gbps)
    }
    
    static func formatUptime(_ uptime: TimeInterval) -> String {
        guard !uptime.isNaN && !uptime.isInfinite && uptime > 0 else { return "0m" }
        let totalMinutes = Int(uptime) / 60
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

