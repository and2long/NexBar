import Darwin
import Foundation

public nonisolated struct DiskCleanerEngine: Sendable {
    public static let flutterCacheNames: [String] = [".dart_tool", "build"]
    public static let skipDirectoryNames: Set<String> = [
        ".git",
        ".gradle",
        ".next",
        ".venv",
        "node_modules",
        "Pods"
    ]

    private static let flutterSDKPattern = #"^\s*sdk:\s*['"]?flutter['"]?\s*(?:#.*)?$"#

    public init() {}

    // MARK: - Public Scan & Clean API

    public func scan(
        includeXcodeDerivedData: Bool,
        includeFlutterCaches: Bool,
        flutterScanRoots: [URL],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CleanupScanReport {
        var warnings: [String] = []
        var candidates: [CleanupCandidate] = []
        var seenPaths = Set<String>()

        let resolvedHome = Self.canonicalURL(homeDirectory) ?? homeDirectory.standardizedFileURL

        if includeXcodeDerivedData {
            let derivedDataURL = resolvedHome
                .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
            if Self.pathExistsViaLstat(derivedDataURL.path) {
                seenPaths.insert(derivedDataURL.path)
                let safety = Self.evaluateSafety(of: derivedDataURL, isXcodeCache: true)
                let size = safety.isSafe ? Self.directorySize(at: derivedDataURL) : 0
                candidates.append(
                    CleanupCandidate(
                        url: derivedDataURL,
                        category: .xcodeDerivedData,
                        sizeBytes: size,
                        safetyStatus: safety
                    )
                )
            }
        }

        if includeFlutterCaches {
            for rawRoot in flutterScanRoots {
                guard Self.pathExistsViaLstat(rawRoot.path) else {
                    warnings.append("扫描目录不存在：\(rawRoot.path)")
                    continue
                }
                guard let resolvedRoot = Self.canonicalURL(rawRoot) else {
                    warnings.append("无法解析扫描目录：\(rawRoot.path)")
                    continue
                }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: resolvedRoot.path, isDirectory: &isDir),
                      isDir.boolValue else {
                    warnings.append("扫描路径不是目录：\(rawRoot.path)")
                    continue
                }

                let found = Self.findFlutterCaches(under: resolvedRoot, warnings: &warnings)
                for (cacheURL, projectName, cacheName) in found {
                    guard seenPaths.insert(cacheURL.path).inserted else { continue }
                    guard Self.pathExistsViaLstat(cacheURL.path) else { continue }

                    let safety = Self.evaluateSafety(of: cacheURL, isXcodeCache: false)
                    let size = Self.directorySizeIfRegularDirectory(at: cacheURL)
                    candidates.append(
                        CleanupCandidate(
                            url: cacheURL,
                            category: .flutterCache(projectName: projectName, cacheName: cacheName),
                            sizeBytes: size,
                            safetyStatus: safety
                        )
                    )
                }
            }
        }

        // Keep Xcode DerivedData first, then sort Flutter caches by size descending then path.
        candidates.sort { lhs, rhs in
            if lhs.category.isXcode != rhs.category.isXcode {
                return lhs.category.isXcode
            }
            if lhs.safetyStatus.isSafe != rhs.safetyStatus.isSafe {
                return lhs.safetyStatus.isSafe
            }
            if lhs.sizeBytes != rhs.sizeBytes {
                return lhs.sizeBytes > rhs.sizeBytes
            }
            return lhs.url.path < rhs.url.path
        }

        return CleanupScanReport(candidates: candidates, warnings: warnings)
    }

    public func clean(
        candidates: [CleanupCandidate],
        mode: DeletionMode
    ) -> CleanupExecutionResult {
        var deletedCount = 0
        var reclaimedBytes: Int64 = 0
        var failures: [CleanupFailure] = []

        for item in candidates where item.isSelected {
            guard Self.pathExistsViaLstat(item.url.path) else {
                continue
            }

            // Re-verify all safety guards right before deletion to prevent TOCTOU races.
            let safety = Self.evaluateSafety(of: item.url, isXcodeCache: item.category.isXcode)
            guard safety.isSafe else {
                failures.append(
                    CleanupFailure(
                        url: item.url,
                        reason: safety.protectionReason ?? "未通过安全校验"
                    )
                )
                continue
            }

            do {
                switch mode {
                case .permanent:
                    try FileManager.default.removeItem(at: item.url)
                case .trash:
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingURL)
                }
                deletedCount += 1
                reclaimedBytes += item.sizeBytes
            } catch {
                failures.append(CleanupFailure(url: item.url, reason: error.localizedDescription))
            }
        }

        return CleanupExecutionResult(
            deletedCount: deletedCount,
            reclaimedBytes: reclaimedBytes,
            failures: failures,
            mode: mode
        )
    }

    // MARK: - Flutter Project Discovery (matches clean-build-caches.py)

    public static func isFlutterPubspecContent(_ content: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: flutterSDKPattern,
            options: [.anchorsMatchLines]
        ) else {
            return false
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.firstMatch(in: content, options: [], range: range) != nil
    }

    private static func findFlutterCaches(
        under root: URL,
        warnings: inout [String]
    ) -> [(url: URL, projectName: String, cacheName: String)] {
        let fm = FileManager.default
        var results: [(URL, String, String)] = []
        var stack: [URL] = [root]

        while let directory = stack.popLast() {
            let entries: [URL]
            do {
                entries = try fm.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: []
                )
            } catch {
                warnings.append("无法读取目录 \(directory.path)：\(error.localizedDescription)")
                continue
            }

            var hasPubspec = false
            var subdirectories: [URL] = []

            for entry in entries {
                let name = entry.lastPathComponent
                if name == "pubspec.yaml" {
                    hasPubspec = true
                }
                if skipDirectoryNames.contains(name) {
                    continue
                }
                guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
                    continue
                }
                if values.isSymbolicLink == true {
                    continue
                }
                if values.isDirectory == true {
                    subdirectories.append(entry)
                }
            }

            var isFlutterProject = false
            if hasPubspec {
                let pubspecURL = directory.appendingPathComponent("pubspec.yaml")
                if isRegularFileViaLstat(pubspecURL.path),
                   let text = try? String(contentsOf: pubspecURL, encoding: .utf8),
                   isFlutterPubspecContent(text) {
                    isFlutterProject = true
                    let projectName = directory.lastPathComponent
                    for cacheName in flutterCacheNames {
                        results.append((
                            directory.appendingPathComponent(cacheName, isDirectory: true),
                            projectName,
                            cacheName
                        ))
                    }
                }
            }

            for subdir in subdirectories.reversed() {
                if isFlutterProject && flutterCacheNames.contains(subdir.lastPathComponent) {
                    continue
                }
                stack.append(subdir)
            }
        }

        return results.sorted { $0.0.path < $1.0.path }
    }

    // MARK: - Safety Checks (matches clean-build-caches.py)

    public static func evaluateSafety(of cacheURL: URL, isXcodeCache: Bool) -> CleanupSafetyStatus {
        let path = cacheURL.path
        var targetStat = stat()
        guard lstat(path, &targetStat) == 0 else {
            return .protected(reason: "路径不存在")
        }

        // Must be a regular directory, never a symlink or regular file.
        guard (targetStat.st_mode & S_IFMT) == S_IFDIR else {
            return .protected(reason: "不是常规目录（可能为符号链接或文件）")
        }

        // Resolved canonical path must match target path exactly (no symlink indirection).
        guard let canonical = canonicalPath(path), canonical == path else {
            return .protected(reason: "包含符号链接路径")
        }

        // Must not be a mount point (device ID must match parent directory).
        if isMountPoint(path: path, targetStat: targetStat) {
            return .protected(reason: "路径为挂载点")
        }

        // For non-Xcode caches, refuse deletion if Git tracks any files inside it.
        if !isXcodeCache {
            switch checkGitTrackedFiles(for: cacheURL) {
            case .untracked:
                break
            case .tracked:
                return .protected(reason: "包含 Git 已跟踪文件")
            case let .error(message):
                return .protected(reason: "Git 校验失败：\(message)")
            }
        }

        return .safe
    }

    private enum GitTrackCheckResult {
        case untracked
        case tracked
        case error(String)
    }

    private static func checkGitTrackedFiles(for cacheURL: URL) -> GitTrackCheckResult {
        let projectURL = cacheURL.deletingLastPathComponent()
        guard hasGitAncestor(startingAt: projectURL) else {
            return .untracked
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectURL.path, "ls-files", "--", cacheURL.lastPathComponent]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .error(error.localizedDescription)
        }

        // Drain output before waiting to avoid pipe buffer deadlocks.
        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errText = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(process.terminationStatus)"
            return .error(errText.isEmpty ? "exit \(process.terminationStatus)" : errText)
        }

        return outData.isEmpty ? .untracked : .tracked
    }

    private static func hasGitAncestor(startingAt directory: URL) -> Bool {
        var current = directory.standardizedFileURL
        while true {
            let dotGitPath = current.appendingPathComponent(".git").path
            if pathExistsViaLstat(dotGitPath) {
                return true
            }
            if current.path == "/" || current.path.isEmpty {
                return false
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                return false
            }
            current = parent
        }
    }

    // MARK: - POSIX & Size Helpers

    public static func pathExistsViaLstat(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    private static func isRegularFileViaLstat(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFREG
    }

    public static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public static func canonicalURL(_ url: URL) -> URL? {
        guard let resolved = canonicalPath(url.path) else { return nil }
        return URL(fileURLWithPath: resolved)
    }

    private static func isMountPoint(path: String, targetStat: stat) -> Bool {
        let currentURL = URL(fileURLWithPath: path).standardizedFileURL
        if currentURL.path == "/" {
            return true
        }
        let parentPath = currentURL.deletingLastPathComponent().standardizedFileURL.path
        if parentPath == currentURL.path {
            return true
        }
        var parentStat = stat()
        guard lstat(parentPath, &parentStat) == 0 else {
            return true
        }
        return targetStat.st_dev != parentStat.st_dev
    }

    private static func directorySizeIfRegularDirectory(at url: URL) -> Int64 {
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else {
            return 0
        }
        return directorySize(at: url)
    }

    public static func directorySize(at root: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        var stack: [URL] = [root]

        while let current = stack.popLast() {
            guard let items = try? fm.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .totalFileAllocatedSizeKey,
                    .fileSizeKey
                ],
                options: []
            ) else {
                continue
            }

            for item in items {
                guard let values = try? item.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .totalFileAllocatedSizeKey,
                    .fileSizeKey
                ]) else {
                    continue
                }
                if values.isSymbolicLink == true {
                    continue
                }
                if values.isDirectory == true {
                    stack.append(item)
                } else {
                    let size = values.totalFileAllocatedSize ?? values.fileSize ?? 0
                    total += Int64(size)
                }
            }
        }
        return total
    }
}
