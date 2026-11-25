import Foundation
import Observation

@Observable
final class DiskCleanerStore {
    private(set) var candidates: [CleanupCandidate] = []
    private(set) var warnings: [String] = []
    private(set) var lastScannedAt: Date?
    private(set) var isScanning: Bool = false
    private(set) var isCleaning: Bool = false
    private(set) var lastResult: CleanupExecutionResult?

    private let engine = DiskCleanerEngine()
    private let settings: AppSettings
    private let onDiskChanged: () -> Void

    init(settings: AppSettings, onDiskChanged: @escaping () -> Void) {
        self.settings = settings
        self.onDiskChanged = onDiskChanged
    }

    var safeCandidates: [CleanupCandidate] {
        candidates.filter { $0.safetyStatus.isSafe }
    }

    var protectedCandidates: [CleanupCandidate] {
        candidates.filter { !$0.safetyStatus.isSafe }
    }

    var selectedCandidates: [CleanupCandidate] {
        candidates.filter { $0.isSelected && $0.isSelectable }
    }

    var totalSafeSizeBytes: Int64 {
        safeCandidates.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedSizeBytes: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.sizeBytes }
    }

    var allSafeSelected: Bool {
        !safeCandidates.isEmpty && safeCandidates.allSatisfy { $0.isSelected }
    }

    func scan() {
        guard !isScanning && !isCleaning else { return }
        isScanning = true
        lastResult = nil

        let includeXcode = settings.cleanXcodeDerivedData
        let includeFlutter = settings.cleanFlutterCaches
        let scanRoots = settings.resolvedFlutterScanRootURLs
        let engine = self.engine

        Task { [weak self] in
            let report = await Task.detached(priority: .userInitiated) {
                engine.scan(
                    includeXcodeDerivedData: includeXcode,
                    includeFlutterCaches: includeFlutter,
                    flutterScanRoots: scanRoots
                )
            }.value

            guard let self else { return }
            self.candidates = report.candidates
            self.warnings = report.warnings
            self.lastScannedAt = report.scannedAt
            self.isScanning = false
        }
    }

    func toggleSelection(for candidateID: String) {
        guard let index = candidates.firstIndex(where: { $0.id == candidateID }),
              candidates[index].isSelectable else {
            return
        }
        candidates[index].isSelected.toggle()
    }

    func setAllSafeSelected(_ selected: Bool) {
        for index in candidates.indices where candidates[index].isSelectable {
            candidates[index].isSelected = selected
        }
    }

    func cleanSelected() {
        guard !isScanning && !isCleaning else { return }
        let itemsToClean = selectedCandidates
        guard !itemsToClean.isEmpty else { return }

        isCleaning = true
        let mode = settings.deletionMode
        let engine = self.engine

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                engine.clean(candidates: itemsToClean, mode: mode)
            }.value

            guard let self else { return }
            self.lastResult = result
            self.isCleaning = false
            self.onDiskChanged()

            // Remove cleaned items from the visible list while keeping failed/unselected/protected items.
            let failedPaths = Set(result.failures.map { $0.url.path })
            let attemptedPaths = Set(itemsToClean.map { $0.url.path })
            self.candidates.removeAll { candidate in
                attemptedPaths.contains(candidate.url.path) && !failedPaths.contains(candidate.url.path)
            }
        }
    }
}
