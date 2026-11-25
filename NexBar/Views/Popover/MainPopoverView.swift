import Observation
import SwiftUI

enum PopoverTab: String, CaseIterable, Identifiable {
    case monitor = "监控"
    case cleaner = "清理"
    case settings = "设置"

    var id: String { rawValue }
}

@Observable
final class PopoverTabRouter {
    var selectedTab: PopoverTab = .monitor
}

struct MainPopoverView: View {
    let monitor: SystemMonitor
    let cleanerStore: DiskCleanerStore
    let settings: AppSettings
    let tabRouter: PopoverTabRouter
    let onQuit: () -> Void

    var body: some View {
        @Bindable var router = tabRouter

        VStack(spacing: 0) {
            headerBar(selectedTab: $router.selectedTab)
            Divider()

            Group {
                switch tabRouter.selectedTab {
                case .monitor:
                    MonitorTabView(
                        monitor: monitor,
                        onOpenCleaner: {
                            tabRouter.selectedTab = .cleaner
                            if cleanerStore.lastScannedAt == nil && !cleanerStore.isScanning {
                                cleanerStore.scan()
                            }
                        }
                    )
                case .cleaner:
                    CleanerTabView(
                        cleanerStore: cleanerStore,
                        settings: settings,
                        onOpenSettings: {
                            tabRouter.selectedTab = .settings
                        }
                    )
                case .settings:
                    SettingsTabView(
                        settings: settings,
                        onQuit: onQuit
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 328, height: 524)
    }

    private func headerBar(selectedTab: Binding<PopoverTab>) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image("BrandLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                Text("NexBar")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            Picker("", selection: selectedTab) {
                ForEach(PopoverTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
