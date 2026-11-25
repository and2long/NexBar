import Foundation
import Observation
import ServiceManagement

@Observable
final class AppSettings {
    private enum Keys {
        static let showCPUInStatusBar = "nexbar.showCPUInStatusBar"
        static let showNetworkInStatusBar = "nexbar.showNetworkInStatusBar"
        static let cleanXcodeDerivedData = "nexbar.cleanXcodeDerivedData"
        static let cleanFlutterCaches = "nexbar.cleanFlutterCaches"
        static let flutterScanRoots = "nexbar.flutterScanRoots"
    }

    static let defaultFlutterScanRoot = "~/projects"

    let refreshInterval: TimeInterval = 2.0
    let deletionMode: DeletionMode = .permanent

    private let defaults: UserDefaults

    var showCPUInStatusBar: Bool {
        didSet {
            if !showCPUInStatusBar && !showNetworkInStatusBar {
                showNetworkInStatusBar = true
            }
            defaults.set(showCPUInStatusBar, forKey: Keys.showCPUInStatusBar)
            onStatusBarConfigChanged?()
        }
    }

    var showNetworkInStatusBar: Bool {
        didSet {
            if !showCPUInStatusBar && !showNetworkInStatusBar {
                showCPUInStatusBar = true
            }
            defaults.set(showNetworkInStatusBar, forKey: Keys.showNetworkInStatusBar)
            onStatusBarConfigChanged?()
        }
    }

    var cleanXcodeDerivedData: Bool {
        didSet {
            defaults.set(cleanXcodeDerivedData, forKey: Keys.cleanXcodeDerivedData)
        }
    }

    var cleanFlutterCaches: Bool {
        didSet {
            defaults.set(cleanFlutterCaches, forKey: Keys.cleanFlutterCaches)
        }
    }

    var flutterScanRoots: [String] {
        didSet {
            defaults.set(flutterScanRoots, forKey: Keys.flutterScanRoots)
        }
    }

    var launchAtLogin: Bool = false
    var launchAtLoginError: String?

    var onStatusBarConfigChanged: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.showCPUInStatusBar = defaults.object(forKey: Keys.showCPUInStatusBar) as? Bool ?? true
        self.showNetworkInStatusBar = defaults.object(forKey: Keys.showNetworkInStatusBar) as? Bool ?? true
        self.cleanXcodeDerivedData = defaults.object(forKey: Keys.cleanXcodeDerivedData) as? Bool ?? true
        self.cleanFlutterCaches = defaults.object(forKey: Keys.cleanFlutterCaches) as? Bool ?? true

        if let savedRoots = defaults.stringArray(forKey: Keys.flutterScanRoots), !savedRoots.isEmpty {
            self.flutterScanRoots = savedRoots
        } else {
            self.flutterScanRoots = [Self.defaultFlutterScanRoot]
        }

        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func addFlutterScanRoot(_ url: URL) {
        let normalized = Self.abbreviateHomePath(url.standardizedFileURL.path)
        guard !flutterScanRoots.contains(normalized) else { return }
        flutterScanRoots.append(normalized)
    }

    func removeFlutterScanRoot(_ path: String) {
        flutterScanRoots.removeAll { $0 == path }
    }

    func resetDefaultFlutterScanRoots() {
        flutterScanRoots = [Self.defaultFlutterScanRoot]
    }

    var resolvedFlutterScanRootURLs: [URL] {
        [Self.expandPath(Self.defaultFlutterScanRoot)]
    }

    static func expandPath(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    static func abbreviateHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
