import Darwin
import Foundation

public nonisolated struct CPUCoreTicks: Sendable, Equatable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public nonisolated final class CPUSampler: @unchecked Sendable {
    private var previousTicks: [CPUCoreTicks]?

    public init() {}

    public func sample() -> CPUSample {
        let currentTicks = Self.readCoreTicks()
        guard !currentTicks.isEmpty else {
            return .zero
        }
        defer { previousTicks = currentTicks }
        guard let previousTicks else {
            return CPUSample(
                totalUsage: 0,
                userUsage: 0,
                systemUsage: 0,
                idleUsage: 1,
                perCoreUsage: Array(repeating: 0, count: currentTicks.count)
            )
        }
        return Self.computeSample(previous: previousTicks, current: currentTicks)
    }

    public static func computeSample(previous: [CPUCoreTicks], current: [CPUCoreTicks]) -> CPUSample {
        let count = min(previous.count, current.count)
        guard count > 0 else { return .zero }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0
        var perCore: [Double] = []
        perCore.reserveCapacity(count)

        for i in 0..<count {
            let dUser = UInt64(current[i].user &- previous[i].user)
            let dSystem = UInt64(current[i].system &- previous[i].system)
            let dIdle = UInt64(current[i].idle &- previous[i].idle)
            let dNice = UInt64(current[i].nice &- previous[i].nice)

            totalUser &+= dUser
            totalSystem &+= dSystem
            totalIdle &+= dIdle
            totalNice &+= dNice

            let coreTotal = dUser + dSystem + dIdle + dNice
            if coreTotal > 0 {
                let active = Double(dUser + dSystem + dNice) / Double(coreTotal)
                perCore.append(min(1, max(0, active)))
            } else {
                perCore.append(0)
            }
        }

        let grandTotal = totalUser + totalSystem + totalIdle + totalNice
        guard grandTotal > 0 else {
            return CPUSample(
                totalUsage: 0,
                userUsage: 0,
                systemUsage: 0,
                idleUsage: 1,
                perCoreUsage: perCore
            )
        }

        let denom = Double(grandTotal)
        let userRatio = min(1, max(0, Double(totalUser + totalNice) / denom))
        let systemRatio = min(1, max(0, Double(totalSystem) / denom))
        let idleRatio = min(1, max(0, Double(totalIdle) / denom))
        let totalUsage = min(1, max(0, userRatio + systemRatio))

        return CPUSample(
            totalUsage: totalUsage,
            userUsage: userRatio,
            systemUsage: systemRatio,
            idleUsage: idleRatio,
            perCoreUsage: perCore
        )
    }

    public static func readCoreTicks() -> [CPUCoreTicks] {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return []
        }

        defer {
            let byteCount = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), byteCount)
        }

        let coreCount = Int(numCPUs)
        let stride = Int(CPU_STATE_MAX)
        var ticks: [CPUCoreTicks] = []
        ticks.reserveCapacity(coreCount)

        for core in 0..<coreCount {
            let base = core * stride
            let user = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)])
            ticks.append(CPUCoreTicks(user: user, system: system, idle: idle, nice: nice))
        }

        return ticks
    }
}
