import Darwin
import Foundation

public nonisolated struct NetworkInterfaceSnapshot: Sendable, Equatable {
    public let timestamp: TimeInterval
    public let receivedBytesByInterface: [String: UInt64]
    public let sentBytesByInterface: [String: UInt64]

    public init(
        timestamp: TimeInterval,
        receivedBytesByInterface: [String: UInt64],
        sentBytesByInterface: [String: UInt64]
    ) {
        self.timestamp = timestamp
        self.receivedBytesByInterface = receivedBytesByInterface
        self.sentBytesByInterface = sentBytesByInterface
    }

    public var totalReceived: UInt64 {
        receivedBytesByInterface.values.reduce(0, &+)
    }

    public var totalSent: UInt64 {
        sentBytesByInterface.values.reduce(0, &+)
    }
}

public nonisolated final class NetworkSampler: @unchecked Sendable {
    private var previousSnapshot: NetworkInterfaceSnapshot?
    private var sessionReceived: UInt64 = 0
    private var sessionSent: UInt64 = 0

    public init() {}

    public func sample() -> NetworkSample {
        let current = Self.readInterfaceSnapshot(timestamp: ProcessInfo.processInfo.systemUptime)
        defer { previousSnapshot = current }

        let result = Self.computeSample(
            previous: previousSnapshot,
            current: current,
            accumulatedReceived: sessionReceived,
            accumulatedSent: sessionSent
        )
        sessionReceived = result.totalReceivedBytes
        sessionSent = result.totalSentBytes
        return result
    }

    /// Count physical/cellular interfaces only to avoid double-counting VPN tunnels (utun*) or AWDL/AirDrop.
    public static func isCountedInterface(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    public static func computeSample(
        previous: NetworkInterfaceSnapshot?,
        current: NetworkInterfaceSnapshot,
        accumulatedReceived: UInt64 = 0,
        accumulatedSent: UInt64 = 0
    ) -> NetworkSample {
        let fallbackInterface = current.receivedBytesByInterface.keys.sorted().first

        guard let previous else {
            return NetworkSample(
                downloadBytesPerSec: 0,
                uploadBytesPerSec: 0,
                totalReceivedBytes: accumulatedReceived,
                totalSentBytes: accumulatedSent,
                activeInterfaceName: fallbackInterface
            )
        }

        let elapsed = current.timestamp - previous.timestamp
        // Guard against sleep/wake gaps or non-positive intervals producing artificial spikes.
        guard elapsed > 0.05 && elapsed <= 15.0 else {
            return NetworkSample(
                downloadBytesPerSec: 0,
                uploadBytesPerSec: 0,
                totalReceivedBytes: accumulatedReceived,
                totalSentBytes: accumulatedSent,
                activeInterfaceName: fallbackInterface
            )
        }

        var deltaRx: UInt64 = 0
        var deltaTx: UInt64 = 0
        var busiestInterface: String?
        var busiestDelta: UInt64 = 0

        for (name, curRx) in current.receivedBytesByInterface {
            let curTx = current.sentBytesByInterface[name] ?? 0
            let prevRx = previous.receivedBytesByInterface[name]
            let prevTx = previous.sentBytesByInterface[name]

            // Only diff interfaces present in both snapshots and without counter reset.
            let rxDiff = (prevRx != nil && curRx >= prevRx!) ? (curRx - prevRx!) : 0
            let txDiff = (prevTx != nil && curTx >= prevTx!) ? (curTx - prevTx!) : 0

            deltaRx &+= rxDiff
            deltaTx &+= txDiff

            let combined = rxDiff &+ txDiff
            if combined > busiestDelta {
                busiestDelta = combined
                busiestInterface = name
            }
        }

        return NetworkSample(
            downloadBytesPerSec: Double(deltaRx) / elapsed,
            uploadBytesPerSec: Double(deltaTx) / elapsed,
            totalReceivedBytes: accumulatedReceived &+ deltaRx,
            totalSentBytes: accumulatedSent &+ deltaTx,
            activeInterfaceName: busiestInterface ?? fallbackInterface
        )
    }

    public static func readInterfaceSnapshot(timestamp: TimeInterval) -> NetworkInterfaceSnapshot {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length: Int = 0

        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return NetworkInterfaceSnapshot(
                timestamp: timestamp,
                receivedBytesByInterface: [:],
                sentBytesByInterface: [:]
            )
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else {
            return NetworkInterfaceSnapshot(
                timestamp: timestamp,
                receivedBytesByInterface: [:],
                sentBytesByInterface: [:]
            )
        }

        var rxByInterface: [String: UInt64] = [:]
        var txByInterface: [String: UInt64] = [:]

        buffer.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr>.size
            let header2Size = MemoryLayout<if_msghdr2>.size

            while offset + headerSize <= length {
                var baseHeader = if_msghdr()
                memcpy(&baseHeader, base.advanced(by: offset), headerSize)

                let msgLen = Int(baseHeader.ifm_msglen)
                guard msgLen > 0, offset + msgLen <= length else { break }

                if Int32(baseHeader.ifm_type) == RTM_IFINFO2 && msgLen >= header2Size {
                    var header2 = if_msghdr2()
                    memcpy(&header2, base.advanced(by: offset), header2Size)

                    let flags = Int32(header2.ifm_flags)
                    let isUp = (flags & IFF_UP) != 0
                    let isRunning = (flags & IFF_RUNNING) != 0
                    let isLoopback = (flags & IFF_LOOPBACK) != 0

                    if isUp && isRunning && !isLoopback {
                        var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                        if if_indextoname(UInt32(header2.ifm_index), &nameBuf) != nil {
                            let name = String(cString: nameBuf)
                            if isCountedInterface(name) {
                                rxByInterface[name] = header2.ifm_data.ifi_ibytes
                                txByInterface[name] = header2.ifm_data.ifi_obytes
                            }
                        }
                    }
                }

                offset += msgLen
            }
        }

        return NetworkInterfaceSnapshot(
            timestamp: timestamp,
            receivedBytesByInterface: rxByInterface,
            sentBytesByInterface: txByInterface
        )
    }
}
