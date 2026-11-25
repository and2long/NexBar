import Foundation

public nonisolated enum ByteRateFormatter {
    /// Compact fixed-style rate string for the macOS menu bar with K/s as the minimum unit (e.g. "0.0 K/s", "128 K/s", "2.4 M/s").
    public static func compactRate(_ bytesPerSecond: Double) -> String {
        let clamped = max(0, bytesPerSecond.isFinite ? bytesPerSecond : 0)
        let kb = clamped / 1_024
        if kb < 100 {
            return String(format: "%.1f K/s", kb)
        }
        if kb < 1_024 {
            return String(format: "%.0f K/s", kb)
        }
        let mb = kb / 1_024
        if mb < 100 {
            return String(format: "%.1f M/s", mb)
        }
        if mb < 1_024 {
            return String(format: "%.0f M/s", mb)
        }
        let gb = mb / 1_024
        return String(format: "%.2f G/s", gb)
    }

    /// Detailed rate string for the popover cards with KB/s as the minimum unit (e.g. "0.0 KB/s", "12.4 KB/s", "2.45 MB/s").
    public static func detailedRate(_ bytesPerSecond: Double) -> String {
        let clamped = max(0, bytesPerSecond.isFinite ? bytesPerSecond : 0)
        let kb = clamped / 1_024
        if kb < 1_024 {
            return String(format: "%.1f KB/s", kb)
        }
        let mb = kb / 1_024
        if mb < 1_024 {
            return String(format: "%.2f MB/s", mb)
        }
        let gb = mb / 1_024
        return String(format: "%.2f GB/s", gb)
    }

    /// Formats a byte count using macOS file-style units (KB/MB/GB/TB).
    public static func byteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(0, bytes))
    }

    public static func byteCount(_ bytes: UInt64) -> String {
        let clamped = bytes > UInt64(Int64.max) ? Int64.max : Int64(bytes)
        return byteCount(clamped)
    }

    public static func percentString(_ ratio: Double) -> String {
        let pct = Int((min(1, max(0, ratio)) * 100).rounded())
        return "\(pct)%"
    }
}
