import AppKit
import SwiftUI

struct CleanerTabView: View {
    let cleanerStore: DiskCleanerStore
    let settings: AppSettings
    let onOpenSettings: () -> Void

    @State private var isConfirmingPermanentDelete = false

    var body: some View {
        VStack(spacing: 0) {
            topSummaryBar
            Divider()

            if isConfirmingPermanentDelete {
                permanentDeleteConfirmBanner
                Divider()
            }

            if let result = cleanerStore.lastResult {
                resultBanner(result)
                Divider()
            }

            contentArea
        }
    }

    private var topSummaryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cleanerStore.lastScannedAt == nil ? "构建缓存清理" : "已选可释放空间")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(ByteRateFormatter.byteCount(cleanerStore.selectedSizeBytes))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        isConfirmingPermanentDelete = false
                        cleanerStore.scan()
                    } label: {
                        Label(
                            cleanerStore.lastScannedAt == nil ? "扫描" : "重扫",
                            systemImage: "magnifyingglass"
                        )
                    }
                    .controlSize(.small)
                    .disabled(cleanerStore.isScanning || cleanerStore.isCleaning)

                    Button {
                        isConfirmingPermanentDelete = true
                    } label: {
                        Text("清理")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(
                        cleanerStore.selectedCandidates.isEmpty
                            || cleanerStore.isScanning
                            || cleanerStore.isCleaning
                    )
                }
            }

            HStack(spacing: 8) {
                if !cleanerStore.safeCandidates.isEmpty {
                    Button {
                        cleanerStore.setAllSafeSelected(!cleanerStore.allSafeSelected)
                    } label: {
                        Text(cleanerStore.allSafeSelected ? "取消全选" : "全选可清理项")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.link)
                }

                Spacer()

                Button("规则设置", action: onOpenSettings)
                    .font(.system(size: 11))
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var permanentDeleteConfirmBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(
                    "确认永久删除 \(cleanerStore.selectedCandidates.count) 个目录（共 \(ByteRateFormatter.byteCount(cleanerStore.selectedSizeBytes))）？此操作不可撤销。"
                )
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("取消") {
                    isConfirmingPermanentDelete = false
                }
                .controlSize(.small)

                Button("确认永久删除", role: .destructive) {
                    isConfirmingPermanentDelete = false
                    cleanerStore.cleanSelected()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.10))
    }

    private func resultBanner(_ result: CleanupExecutionResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(result.failures.isEmpty ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                let verb = result.mode == .permanent ? "已永久清理" : "已移入废纸篓"
                Text("\(verb) \(result.deletedCount) 个目录，释放 \(ByteRateFormatter.byteCount(result.reclaimedBytes))")
                    .font(.system(size: 11.5, weight: .medium))
                if !result.failures.isEmpty {
                    Text("另有 \(result.failures.count) 项跳过或失败：\(result.failures.first?.reason ?? "")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((result.failures.isEmpty ? Color.green : Color.orange).opacity(0.10))
    }

    @ViewBuilder
    private var contentArea: some View {
        if cleanerStore.isScanning {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在扫描 Xcode DerivedData 与 Flutter 构建缓存...")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if cleanerStore.isCleaning {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在执行安全复检并清理选中缓存...")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if cleanerStore.lastScannedAt == nil {
            VStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("点击「扫描」检查可清理的构建缓存")
                    .font(.system(size: 12.5, weight: .medium))
                Text("内置 Xcode DerivedData 与 Flutter（.dart_tool / build）规则，自动跳过软链、挂载点及 Git 已跟踪目录。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if cleanerStore.candidates.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                Text("未发现可清理的缓存目录")
                    .font(.system(size: 12.5, weight: .medium))
                if !cleanerStore.warnings.isEmpty {
                    Text(cleanerStore.warnings.joined(separator: "\n"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if !cleanerStore.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(cleanerStore.warnings, id: \.self) { warning in
                                Text("• \(warning)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if !cleanerStore.safeCandidates.isEmpty {
                        sectionHeader("可安全清理 (\(cleanerStore.safeCandidates.count))")
                        ForEach(cleanerStore.safeCandidates) { item in
                            candidateRow(item)
                        }
                    }

                    if !cleanerStore.protectedCandidates.isEmpty {
                        sectionHeader("安全护栏已跳过 (\(cleanerStore.protectedCandidates.count))")
                            .padding(.top, 4)
                        ForEach(cleanerStore.protectedCandidates) { item in
                            candidateRow(item)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func candidateRow(_ item: CleanupCandidate) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if item.isSelectable {
                Button {
                    cleanerStore.toggleSelection(for: item.id)
                } label: {
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(item.isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                    .help(item.safetyStatus.protectionReason ?? "已保护")
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.category.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Text(item.category.badgeText)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            (item.category.isXcode ? Color.blue : Color.teal).opacity(0.14),
                            in: Capsule()
                        )
                        .foregroundStyle(item.category.isXcode ? .blue : .teal)
                }

                Text(AppSettings.abbreviateHomePath(item.url.path))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let reason = item.safetyStatus.protectionReason {
                    Text("已保护：\(reason)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 6)

            Text(ByteRateFormatter.byteCount(item.sizeBytes))
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(item.isSelectable ? .primary : .secondary)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("在访达中显示")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            (item.isSelectable ? Color.primary.opacity(0.04) : Color.orange.opacity(0.06)),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
