import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var statusBarView: StatusBarMonitorView!
    private var popover: NSPopover!

    private let settings = AppSettings()
    private var monitor: SystemMonitor!
    private var cleanerStore: DiskCleanerStore!
    private var tabRouter = PopoverTabRouter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        monitor = SystemMonitor(settings: settings)
        cleanerStore = DiskCleanerStore(settings: settings) { [weak self] in
            self?.monitor.refreshDiskNow()
        }

        setupStatusItem()
        setupPopover()

        monitor.onMetricsUpdated = { [weak self] in
            self?.refreshStatusBarView()
        }
        settings.onStatusBarConfigChanged = { [weak self] in
            self?.refreshStatusBarView()
        }

        monitor.start()
        refreshStatusBarView()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarView = StatusBarMonitorView(frame: NSRect(x: 0, y: 0, width: 117, height: 22))
        statusBarView.autoresizingMask = [.height]

        if let button = statusItem.button {
            button.title = ""
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.addSubview(statusBarView)
        }
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 328, height: 524)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let rootView = MainPopoverView(
            monitor: monitor,
            cleanerStore: cleanerStore,
            settings: settings,
            tabRouter: tabRouter,
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        popover.contentViewController = NSHostingController(rootView: rootView)
        self.popover = popover
    }

    private func refreshStatusBarView() {
        guard let statusBarView, let statusItem else { return }
        statusBarView.update(
            cpuUsage: monitor.cpu.totalUsage,
            uploadRate: monitor.network.uploadBytesPerSec,
            downloadRate: monitor.network.downloadBytesPerSec,
            showCPU: settings.showCPUInStatusBar,
            showNetwork: settings.showNetworkInStatusBar
        )

        let width = statusBarView.requiredWidth
        if abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
        }
        if let button = statusItem.button {
            statusBarView.frame = NSRect(x: 0, y: 0, width: width, height: button.bounds.height)
        }
    }

    @objc private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            monitor.refreshDiskNow()
            settings.refreshLaunchAtLoginStatus()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        if popover.isShown {
            popover.performClose(nil)
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开 NexBar", action: #selector(openFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let scanItem = NSMenuItem(title: "扫描磁盘缓存", action: #selector(openAndScanFromMenu), keyEquivalent: "")
        scanItem.target = self
        menu.addItem(scanItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 NexBar", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openFromMenu() {
        togglePopover()
    }

    @objc private func openAndScanFromMenu() {
        tabRouter.selectedTab = .cleaner
        if !popover.isShown {
            togglePopover()
        }
        cleanerStore.scan()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }
}
