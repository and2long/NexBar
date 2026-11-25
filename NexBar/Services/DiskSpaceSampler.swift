import Foundation

public nonisolated enum DiskSpaceSampler {
    public static func sampleRootVolume() -> DiskSpaceSnapshot {
        let rootURL = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? rootURL.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else {
            return .zero
        }
        let available: Int64
        if let important = values.volumeAvailableCapacityForImportantUsage {
            available = important
        } else if let standard = values.volumeAvailableCapacity {
            available = Int64(standard)
        } else {
            available = 0
        }
        return DiskSpaceSnapshot(totalBytes: Int64(total), availableBytes: available)
    }
}
