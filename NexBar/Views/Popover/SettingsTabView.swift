import SwiftUI

struct SettingsTabView: View {
    let settings: AppSettings
    let onQuit: () -> Void

    var body: some View {
        @Bindable var bindableSettings = settings

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    generalSection(settings: $bindableSettings)
                    cleanerRulesSection(settings: $bindableSettings)
                }
                .padding(12)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            footerSection
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }

    private func generalSection(settings: Bindable<AppSettings>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("状态栏与通用")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle(
                "登录时自动启动",
                isOn: Binding(
                    get: { self.settings.launchAtLogin },
                    set: { self.settings.setLaunchAtLogin($0) }
                )
            )
            .font(.system(size: 12))

            if let error = self.settings.launchAtLoginError {
                Text("开机自启设置提示：\(error)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }

            Toggle("状态栏显示 CPU 负载", isOn: settings.showCPUInStatusBar)
                .font(.system(size: 12))
            Toggle("状态栏显示上下行网速", isOn: settings.showNetworkInStatusBar)
                .font(.system(size: 12))
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func cleanerRulesSection(settings: Bindable<AppSettings>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("磁盘清理规则")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle(isOn: settings.cleanXcodeDerivedData) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Xcode DerivedData")
                        .font(.system(size: 12, weight: .medium))
                    Text("~/Library/Developer/Xcode/DerivedData")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: settings.cleanFlutterCaches) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flutter 项目缓存")
                        .font(.system(size: 12, weight: .medium))
                    Text("~/projects（自动识别 sdk: flutter，清理 .dart_tool 与 build）")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footerSection: some View {
        HStack {
            Text("NexBar v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("退出 NexBar", role: .destructive, action: onQuit)
                .controlSize(.small)
        }
    }
}
