import Foundation

public nonisolated struct CPUSample: Sendable, Equatable {
    public var totalUsage: Double
    public var userUsage: Double
    public var systemUsage: Double
    public var idleUsage: Double
    public var perCoreUsage: [Double]

    public init(
        totalUsage: Double = 0,
        userUsage: Double = 0,
        systemUsage: Double = 0,
        idleUsage: Double = 1,
        perCoreUsage: [Double] = []
    ) {
        self.totalUsage = totalUsage
        self.userUsage = userUsage
        self.systemUsage = systemUsage
        self.idleUsage = idleUsage
        self.perCoreUsage = perCoreUsage
    }

    public static let zero = CPUSample()
}

public nonisolated struct NetworkSample: Sendable, Equatable {
    public var downloadBytesPerSec: Double
    public var uploadBytesPerSec: Double
    public var totalReceivedBytes: UInt64
    public var totalSentBytes: UInt64
    public var activeInterfaceName: String?

    public init(
        downloadBytesPerSec: Double = 0,
        uploadBytesPerSec: Double = 0,
        totalReceivedBytes: UInt64 = 0,
        totalSentBytes: UInt64 = 0,
        activeInterfaceName: String? = nil
    ) {
        self.downloadBytesPerSec = downloadBytesPerSec
        self.uploadBytesPerSec = uploadBytesPerSec
        self.totalReceivedBytes = totalReceivedBytes
        self.totalSentBytes = totalSentBytes
        self.activeInterfaceName = activeInterfaceName
    }

    public static let zero = NetworkSample()
}

public nonisolated struct DiskSpaceSnapshot: Sendable, Equatable {
    public var totalBytes: Int64
    public var availableBytes: Int64

    public var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }

    public var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    public init(totalBytes: Int64 = 0, availableBytes: Int64 = 0) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }

    public static let zero = DiskSpaceSnapshot()
}

public nonisolated struct RingBuffer<Element: Sendable>: Sendable {
    public let capacity: Int
    public private(set) var values: [Element]

    public init(capacity: Int, initialValue: Element? = nil) {
        self.capacity = max(1, capacity)
        if let initialValue {
            self.values = Array(repeating: initialValue, count: self.capacity)
        } else {
            self.values = []
        }
    }

    public mutating func append(_ element: Element) {
        if values.count >= capacity {
            values.removeFirst(values.count - capacity + 1)
        }
        values.append(element)
    }
}
