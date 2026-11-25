import Foundation

public nonisolated enum CleanupCategory: Sendable, Equatable, Hashable {
    case xcodeDerivedData
    case flutterCache(projectName: String, cacheName: String)

    public var displayTitle: String {
        switch self {
        case .xcodeDerivedData:
            return "Xcode DerivedData"
        case let .flutterCache(projectName, _):
            return projectName
        }
    }

    public var badgeText: String {
        switch self {
        case .xcodeDerivedData:
            return "DerivedData"
        case let .flutterCache(_, cacheName):
            return cacheName
        }
    }

    public var isXcode: Bool {
        if case .xcodeDerivedData = self { return true }
        return false
    }
}

public nonisolated enum CleanupSafetyStatus: Sendable, Equatable, Hashable {
    case safe
    case protected(reason: String)

    public var isSafe: Bool {
        if case .safe = self { return true }
        return false
    }

    public var protectionReason: String? {
        if case let .protected(reason) = self { return reason }
        return nil
    }
}

public nonisolated struct CleanupCandidate: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let url: URL
    public let category: CleanupCategory
    public let sizeBytes: Int64
    public let safetyStatus: CleanupSafetyStatus
    public var isSelected: Bool

    public init(
        url: URL,
        category: CleanupCategory,
        sizeBytes: Int64,
        safetyStatus: CleanupSafetyStatus,
        isSelected: Bool? = nil
    ) {
        self.id = url.path
        self.url = url
        self.category = category
        self.sizeBytes = sizeBytes
        self.safetyStatus = safetyStatus
        self.isSelected = isSelected ?? safetyStatus.isSafe
    }

    public var isSelectable: Bool {
        safetyStatus.isSafe
    }
}

public nonisolated enum DeletionMode: String, CaseIterable, Sendable, Identifiable {
    case permanent
    case trash

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .permanent:
            return "直接永久删除"
        case .trash:
            return "移入废纸篓"
        }
    }

    public var subtitle: String {
        switch self {
        case .permanent:
            return "立即释放磁盘空间（与 clean-build-caches.py 一致）"
        case .trash:
            return "保留恢复机会，清空废纸篓后释放空间"
        }
    }
}

public nonisolated struct CleanupScanReport: Sendable, Equatable {
    public let candidates: [CleanupCandidate]
    public let warnings: [String]
    public let scannedAt: Date

    public init(candidates: [CleanupCandidate], warnings: [String] = [], scannedAt: Date = Date()) {
        self.candidates = candidates
        self.warnings = warnings
        self.scannedAt = scannedAt
    }

    public var safeCandidates: [CleanupCandidate] {
        candidates.filter { $0.safetyStatus.isSafe }
    }

    public var protectedCandidates: [CleanupCandidate] {
        candidates.filter { !$0.safetyStatus.isSafe }
    }
}

public nonisolated struct CleanupFailure: Sendable, Equatable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

public nonisolated struct CleanupExecutionResult: Sendable, Equatable {
    public let deletedCount: Int
    public let reclaimedBytes: Int64
    public let failures: [CleanupFailure]
    public let mode: DeletionMode

    public init(
        deletedCount: Int,
        reclaimedBytes: Int64,
        failures: [CleanupFailure],
        mode: DeletionMode
    ) {
        self.deletedCount = deletedCount
        self.reclaimedBytes = reclaimedBytes
        self.failures = failures
        self.mode = mode
    }
}
