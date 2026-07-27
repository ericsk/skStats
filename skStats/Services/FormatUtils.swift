import Foundation

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
