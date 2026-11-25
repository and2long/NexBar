import Darwin
import Foundation

@main
struct NexBarCoreTests {
    static var failures: [String] = []

    static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            let entry = "FAIL [\(file):\(line)] \(message)"
            failures.append(entry)
            fputs("\(entry)\n", stderr)
        }
    }

    static func main() throws {
        testByteRateFormatter()
        testCPUSamplerMath()
        testNetworkSamplerMath()
        testFlutterPubspecDetection()
        try testDiskCleanerEndToEnd()

        if failures.isEmpty {
            print("ALL NEXBAR CORE TESTS PASSED")
            exit(0)
        } else {
            fputs("\(failures.count) test assertion(s) failed.\n", stderr)
            exit(1)
        }
    }

    static func testByteRateFormatter() {
        expect(ByteRateFormatter.compactRate(0) == "0.0 K/s", "Zero rate format uses K/s")
        expect(ByteRateFormatter.compactRate(512) == "0.5 K/s", "Sub-KB rate format uses K/s")
        expect(ByteRateFormatter.compactRate(12_800) == "12.5 K/s", "KB decimal rate format")
        expect(ByteRateFormatter.compactRate(256 * 1_024) == "256 K/s", "KB integer rate format")
        expect(ByteRateFormatter.compactRate(2.5 * 1_024 * 1_024) == "2.5 M/s", "MB rate format")
        expect(ByteRateFormatter.compactRate(1.25 * 1_024 * 1_024 * 1_024) == "1.25 G/s", "GB rate format")
        expect(ByteRateFormatter.compactRate(.nan) == "0.0 K/s", "NaN safety")
        expect(ByteRateFormatter.detailedRate(0) == "0.0 KB/s", "Detailed zero rate uses KB/s")
        expect(ByteRateFormatter.detailedRate(512) == "0.5 KB/s", "Detailed sub-KB rate uses KB/s")
        expect(ByteRateFormatter.percentString(0.246) == "25%", "Percent rounding")
        expect(ByteRateFormatter.percentString(1.5) == "100%", "Percent upper clamp")
        expect(ByteRateFormatter.percentString(-0.2) == "0%", "Percent lower clamp")
    }

    static func testCPUSamplerMath() {
        let prev = [
            CPUCoreTicks(user: 100, system: 50, idle: 850, nice: 0),
            CPUCoreTicks(user: 200, system: 100, idle: 700, nice: 0)
        ]
        let curr = [
            CPUCoreTicks(user: 130, system: 60, idle: 910, nice: 0), // Δuser=30, Δsys=10, Δidle=60 -> 40%
            CPUCoreTicks(user: 250, system: 110, idle: 740, nice: 0) // Δuser=50, Δsys=10, Δidle=40 -> 60%
        ]
        let sample = CPUSampler.computeSample(previous: prev, current: curr)
        expect(abs(sample.totalUsage - 0.50) < 0.001, "Expected 50% total CPU, got \(sample.totalUsage)")
        expect(abs(sample.userUsage - 0.40) < 0.001, "Expected 40% user CPU, got \(sample.userUsage)")
        expect(abs(sample.systemUsage - 0.10) < 0.001, "Expected 10% system CPU, got \(sample.systemUsage)")
        expect(abs(sample.idleUsage - 0.50) < 0.001, "Expected 50% idle CPU, got \(sample.idleUsage)")
        expect(sample.perCoreUsage.count == 2, "Expected 2 per-core entries")
        expect(abs(sample.perCoreUsage[0] - 0.40) < 0.001, "Core 0 expected 40%")
        expect(abs(sample.perCoreUsage[1] - 0.60) < 0.001, "Core 1 expected 60%")

        let zeroDelta = CPUSampler.computeSample(previous: curr, current: curr)
        expect(zeroDelta.totalUsage == 0 && zeroDelta.idleUsage == 1, "Zero delta should report 0% busy")

        // Live Mach call should succeed on macOS and return at least 1 core.
        let liveTicks = CPUSampler.readCoreTicks()
        expect(!liveTicks.isEmpty, "Live Mach host_processor_info should return >= 1 core")
    }

    static func testNetworkSamplerMath() {
        expect(NetworkSampler.isCountedInterface("en0"), "en0 should be counted")
        expect(NetworkSampler.isCountedInterface("en7"), "en7 should be counted")
        expect(NetworkSampler.isCountedInterface("pdp_ip0"), "pdp_ip0 should be counted")
        expect(!NetworkSampler.isCountedInterface("lo0"), "lo0 must be excluded")
        expect(!NetworkSampler.isCountedInterface("utun3"), "utun3 must be excluded to prevent VPN double-count")
        expect(!NetworkSampler.isCountedInterface("awdl0"), "awdl0 must be excluded")
        expect(!NetworkSampler.isCountedInterface("bridge0"), "bridge0 must be excluded")

        let t0 = NetworkInterfaceSnapshot(
            timestamp: 100.0,
            receivedBytesByInterface: ["en0": 1_000, "en1": 500],
            sentBytesByInterface: ["en0": 2_000, "en1": 100]
        )
        let t1 = NetworkInterfaceSnapshot(
            timestamp: 102.0,
            receivedBytesByInterface: ["en0": 5_000, "en1": 500],
            sentBytesByInterface: ["en0": 3_000, "en1": 100]
        )
        let normal = NetworkSampler.computeSample(previous: t0, current: t1)
        expect(abs(normal.downloadBytesPerSec - 2_000) < 0.01, "Expected 2000 B/s down, got \(normal.downloadBytesPerSec)")
        expect(abs(normal.uploadBytesPerSec - 500) < 0.01, "Expected 500 B/s up, got \(normal.uploadBytesPerSec)")
        expect(normal.activeInterfaceName == "en0", "Busiest interface should be en0")
        expect(normal.totalReceivedBytes == 4_000 && normal.totalSentBytes == 1_000, "Session byte totals")

        // Sleep/wake gap > 15s should report 0 rate without spikes.
        let afterSleep = NetworkInterfaceSnapshot(
            timestamp: 200.0,
            receivedBytesByInterface: ["en0": 999_000],
            sentBytesByInterface: ["en0": 999_000]
        )
        let wakeSample = NetworkSampler.computeSample(previous: t1, current: afterSleep)
        expect(wakeSample.downloadBytesPerSec == 0 && wakeSample.uploadBytesPerSec == 0, "Sleep gap guard should yield 0")

        // Counter reset (current < previous) should yield 0 instead of underflowing.
        let reset = NetworkInterfaceSnapshot(
            timestamp: 103.0,
            receivedBytesByInterface: ["en0": 100],
            sentBytesByInterface: ["en0": 50]
        )
        let resetSample = NetworkSampler.computeSample(previous: t1, current: reset)
        expect(resetSample.downloadBytesPerSec == 0 && resetSample.uploadBytesPerSec == 0, "Counter reset must not underflow")
    }

    static func testFlutterPubspecDetection() {
        expect(DiskCleanerEngine.isFlutterPubspecContent("dependencies:\n  flutter:\n    sdk: flutter\n"), "Plain sdk: flutter")
        expect(DiskCleanerEngine.isFlutterPubspecContent("    sdk: 'flutter' # comment\n"), "Single-quoted with comment")
        expect(DiskCleanerEngine.isFlutterPubspecContent("    sdk: \"flutter\"\n"), "Double-quoted")
        expect(!DiskCleanerEngine.isFlutterPubspecContent("name: pure_dart\ndependencies:\n  http: ^1.0.0\n"), "Non-Flutter Dart pubspec")
        expect(!DiskCleanerEngine.isFlutterPubspecContent("# sdk: flutter\n"), "Commented-out sdk: flutter must not match")
    }

    static func testDiskCleanerEndToEnd() throws {
        let fm = FileManager.default
        let rawTemp = fm.temporaryDirectory.appendingPathComponent("NexBarTests-\(UUID().uuidString)")
        try fm.createDirectory(at: rawTemp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: rawTemp) }

        guard let tempRoot = DiskCleanerEngine.canonicalURL(rawTemp) else {
            expect(false, "Failed to resolve canonical temp root")
            return
        }

        // 1. Fake home with Xcode DerivedData
        let fakeHome = tempRoot.appendingPathComponent("home")
        let derivedData = fakeHome.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        try fm.createDirectory(at: derivedData, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4096).write(to: derivedData.appendingPathComponent("artifact.bin"))

        // 2. Projects root
        let projectsRoot = fakeHome.appendingPathComponent("projects")
        try fm.createDirectory(at: projectsRoot, withIntermediateDirectories: true)

        // 2a. Normal Flutter project with .dart_tool and build
        let normalFlutter = projectsRoot.appendingPathComponent("normal_flutter")
        try fm.createDirectory(at: normalFlutter.appendingPathComponent(".dart_tool"), withIntermediateDirectories: true)
        try fm.createDirectory(at: normalFlutter.appendingPathComponent("build"), withIntermediateDirectories: true)
        try "name: normal_flutter\ndependencies:\n  flutter:\n    sdk: flutter\n"
            .write(to: normalFlutter.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        try Data(repeating: 0x42, count: 2048).write(to: normalFlutter.appendingPathComponent(".dart_tool/cache.bin"))
        try Data(repeating: 0x43, count: 8192).write(to: normalFlutter.appendingPathComponent("build/output.bin"))

        // 2b. Non-Flutter Dart project (must NOT be flagged)
        let dartOnly = projectsRoot.appendingPathComponent("dart_cli")
        try fm.createDirectory(at: dartOnly.appendingPathComponent(".dart_tool"), withIntermediateDirectories: true)
        try "name: dart_cli\nenvironment:\n  sdk: ^3.0.0\n"
            .write(to: dartOnly.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)

        // 2c. Flutter project hidden inside node_modules (must be SKIPPED)
        let insideNodeModules = projectsRoot.appendingPathComponent("web/node_modules/ignored_flutter")
        try fm.createDirectory(at: insideNodeModules.appendingPathComponent("build"), withIntermediateDirectories: true)
        try "dependencies:\n  flutter:\n    sdk: flutter\n"
            .write(to: insideNodeModules.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)

        // 2d. Flutter project with symlinked build/ (must be PROTECTED)
        let outsideTarget = tempRoot.appendingPathComponent("outside_precious")
        try fm.createDirectory(at: outsideTarget, withIntermediateDirectories: true)
        let symlinkFlutter = projectsRoot.appendingPathComponent("symlink_flutter")
        try fm.createDirectory(at: symlinkFlutter, withIntermediateDirectories: true)
        try "dependencies:\n  flutter:\n    sdk: 'flutter'\n"
            .write(to: symlinkFlutter.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: symlinkFlutter.appendingPathComponent("build"), withDestinationURL: outsideTarget)

        // 2e. Git-tracked Flutter project: build/ has tracked file (PROTECTED), .dart_tool/ is untracked (SAFE)
        let gitFlutter = projectsRoot.appendingPathComponent("git_flutter")
        try fm.createDirectory(at: gitFlutter.appendingPathComponent("build"), withIntermediateDirectories: true)
        try fm.createDirectory(at: gitFlutter.appendingPathComponent(".dart_tool"), withIntermediateDirectories: true)
        try "dependencies:\n  flutter:\n    sdk: \"flutter\"\n"
            .write(to: gitFlutter.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        try "keep me".write(to: gitFlutter.appendingPathComponent("build/tracked.txt"), atomically: true, encoding: .utf8)
        try "temp".write(to: gitFlutter.appendingPathComponent(".dart_tool/temp.txt"), atomically: true, encoding: .utf8)

        try runGit(["init", "-q"], in: gitFlutter)
        try runGit(["add", "build/tracked.txt"], in: gitFlutter)

        // Run scan
        let engine = DiskCleanerEngine()
        let report = engine.scan(
            includeXcodeDerivedData: true,
            includeFlutterCaches: true,
            flutterScanRoots: [projectsRoot],
            homeDirectory: fakeHome
        )

        let byPath = Dictionary(uniqueKeysWithValues: report.candidates.map { ($0.url.path, $0) })

        expect(byPath[derivedData.path]?.safetyStatus == .safe, "Xcode DerivedData should be found and safe")
        expect((byPath[derivedData.path]?.sizeBytes ?? 0) >= 4096, "Xcode DerivedData size should be measured")

        expect(byPath[normalFlutter.appendingPathComponent(".dart_tool").path]?.safetyStatus == .safe, "normal_flutter/.dart_tool safe")
        expect(byPath[normalFlutter.appendingPathComponent("build").path]?.safetyStatus == .safe, "normal_flutter/build safe")

        expect(byPath[dartOnly.appendingPathComponent(".dart_tool").path] == nil, "Non-Flutter Dart project must be ignored")
        expect(byPath[insideNodeModules.appendingPathComponent("build").path] == nil, "node_modules must be skipped")

        let symlinkCandidate = byPath[symlinkFlutter.appendingPathComponent("build").path]
        expect(symlinkCandidate != nil && symlinkCandidate?.safetyStatus.isSafe == false, "Symlinked build/ must be protected")

        let gitBuildCandidate = byPath[gitFlutter.appendingPathComponent("build").path]
        expect(gitBuildCandidate != nil && gitBuildCandidate?.safetyStatus.isSafe == false, "Git-tracked build/ must be protected")
        expect(gitBuildCandidate?.safetyStatus.protectionReason?.contains("Git") == true, "Git protection reason should mention Git")

        let gitDartToolCandidate = byPath[gitFlutter.appendingPathComponent(".dart_tool").path]
        expect(gitDartToolCandidate?.safetyStatus == .safe, "Untracked .dart_tool/ in git repo should be safe")

        // Execute cleanup on all candidates (even if someone tried to force-select a protected item, clean() re-verifies!)
        var forcedCandidates = report.candidates
        for idx in forcedCandidates.indices {
            forcedCandidates[idx].isSelected = true
        }
        let result = engine.clean(candidates: forcedCandidates, mode: .permanent)

        expect(result.deletedCount == 4, "Should delete exactly 4 safe directories, got \(result.deletedCount)")
        expect(result.failures.count == 2, "Should refuse 2 protected directories (symlink + git-tracked), got \(result.failures.count)")
        expect(!fm.fileExists(atPath: derivedData.path), "DerivedData should be deleted")
        expect(!fm.fileExists(atPath: normalFlutter.appendingPathComponent("build").path), "normal_flutter/build should be deleted")
        expect(!fm.fileExists(atPath: gitFlutter.appendingPathComponent(".dart_tool").path), "git_flutter/.dart_tool should be deleted")
        expect(fm.fileExists(atPath: gitFlutter.appendingPathComponent("build/tracked.txt").path), "Git-tracked file MUST survive")
        expect(fm.fileExists(atPath: outsideTarget.path), "Symlink target outside project MUST survive")
    }

    static func runGit(_ args: [String], in directory: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", directory.path] + args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "GitTest", code: Int(p.terminationStatus))
        }
    }
}
