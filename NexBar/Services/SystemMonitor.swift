import Foundation
import Observation

@Observable
final class SystemMonitor {
    private(set) var cpu: CPUSample = .zero
    private(set) var network: NetworkSample = .zero
    private(set) var disk: DiskSpaceSnapshot = .zero

    private(set) var cpuHistory = RingBuffer<Double>(capacity: 60, initialValue: 0)
    private(set) var downloadHistory = RingBuffer<Double>(capacity: 60, initialValue: 0)
    private(set) var uploadHistory = RingBuffer<Double>(capacity: 60, initialValue: 0)

    var onMetricsUpdated: (() -> Void)?

    private let settings: AppSettings
    private let cpuSampler = CPUSampler()
    private let networkSampler = NetworkSampler()
    private var monitorTask: Task<Void, Never>?
    private var tickCount: Int = 0

    init(settings: AppSettings) {
        self.settings = settings
        self.disk = DiskSpaceSampler.sampleRootVolume()
    }

    func start() {
        guard monitorTask == nil else { return }

        // Prime samplers immediately so the first visible interval is accurate.
        let cpuSampler = self.cpuSampler
        let networkSampler = self.networkSampler

        monitorTask = Task { [weak self] in
            let initial = await Task.detached(priority: .utility) {
                (cpuSampler.sample(), networkSampler.sample(), DiskSpaceSampler.sampleRootVolume())
            }.value

            if let self, !Task.isCancelled {
                self.cpu = initial.0
                self.network = initial.1
                self.disk = initial.2
                self.onMetricsUpdated?()
            }

            while !Task.isCancelled {
                let interval = self?.settings.refreshInterval ?? 2.0
                let nanoseconds = UInt64(max(0.5, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { break }

                let shouldRefreshDisk = (self?.tickCount ?? 0) % 15 == 0
                let sampled = await Task.detached(priority: .utility) {
                    let c = cpuSampler.sample()
                    let n = networkSampler.sample()
                    let d = shouldRefreshDisk ? DiskSpaceSampler.sampleRootVolume() : nil
                    return (c, n, d)
                }.value

                guard let self, !Task.isCancelled else { break }
                self.tickCount += 1
                self.cpu = sampled.0
                self.network = sampled.1
                if let diskSnapshot = sampled.2 {
                    self.disk = diskSnapshot
                }
                self.cpuHistory.append(sampled.0.totalUsage)
                self.downloadHistory.append(sampled.1.downloadBytesPerSec)
                self.uploadHistory.append(sampled.1.uploadBytesPerSec)
                self.onMetricsUpdated?()
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func refreshDiskNow() {
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                DiskSpaceSampler.sampleRootVolume()
            }.value
            self?.disk = snapshot
        }
    }

    #if DEBUG
    func applyPreviewSnapshot(
        cpu: CPUSample,
        network: NetworkSample,
        disk: DiskSpaceSnapshot,
        cpuPoints: [Double],
        downloadPoints: [Double],
        uploadPoints: [Double]
    ) {
        self.cpu = cpu
        self.network = network
        self.disk = disk
        self.cpuHistory = RingBuffer<Double>(capacity: 60)
        for p in cpuPoints { self.cpuHistory.append(p) }
        self.downloadHistory = RingBuffer<Double>(capacity: 60)
        for p in downloadPoints { self.downloadHistory.append(p) }
        self.uploadHistory = RingBuffer<Double>(capacity: 60)
        for p in uploadPoints { self.uploadHistory.append(p) }
    }
    #endif
}
