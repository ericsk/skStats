import Foundation

struct FormatUtils {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .memory
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
        if bytes < 1024 { return String(format: "%.0f B", bytes) }
        return byteFormatter.string(fromByteCount: Int64(bytes))
    }
    
    static func formatMemoryGB(_ bytes: Double) -> String {
        let gb = bytes / 1_073_741_824.0 // 1024^3
        return String(format: "%.1f GB", gb)
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
    
    static func formatUptime(_ uptime: TimeInterval) -> String {
        return uptimeFormatter.string(from: uptime) ?? "0m"
    }
}
