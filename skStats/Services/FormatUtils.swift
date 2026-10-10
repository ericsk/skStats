import Foundation

struct FormatUtils {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()
    
    private static let uptimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func formatBytes(_ bytes: Double) -> String {
        guard !bytes.isNaN && !bytes.isInfinite && bytes > 0 else { return "0 B" }
        if bytes < 1024 { return String(format: "%.0f B", bytes) }
        return byteFormatter.string(fromByteCount: Int64(bytes))
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
    
    static func formatPercentage(_ value: Double) -> String {
        guard !value.isNaN && !value.isInfinite else { return "0%" }
        return String(format: "%.0f%%", max(value, 0) * 100)
    }
    
    static func formatCompactRate(_ bytesPerSecond: Double) -> String {
        guard !bytesPerSecond.isNaN && !bytesPerSecond.isInfinite && bytesPerSecond > 0 else { return "0K" }
        let kbps = bytesPerSecond / 1024.0
        if kbps < 1024 {
            return String(format: "%.0fK", kbps)
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
        return uptimeFormatter.string(from: uptime) ?? "0m"
    }
}
