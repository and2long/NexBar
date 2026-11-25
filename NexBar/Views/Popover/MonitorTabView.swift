import SwiftUI

struct MonitorTabView: View {
    let monitor: SystemMonitor
    let onOpenCleaner: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            cpuCard
            networkCard
            diskCard
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("CPU 负载", systemImage: "cpu")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteRateFormatter.percentString(monitor.cpu.totalUsage))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(cpuAccentColor)
            }

            SparklineView(
                series: [
                    SparklineSeries(values: monitor.cpuHistory.values, color: cpuAccentColor, fillOpacity: 0.18)
                ],
                maxValue: 1.0
            )
            .frame(height: 52)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 12) {
                metricPill(title: "用户", value: ByteRateFormatter.percentString(monitor.cpu.userUsage), color: .blue)
                metricPill(title: "系统", value: ByteRateFormatter.percentString(monitor.cpu.systemUsage), color: .orange)
                metricPill(title: "空闲", value: ByteRateFormatter.percentString(monitor.cpu.idleUsage), color: .secondary)
            }

            if !monitor.cpu.perCoreUsage.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("各核心占用 (\(monitor.cpu.perCoreUsage.count) 核)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(monitor.cpu.perCoreUsage.enumerated()), id: \.offset) { _, usage in
                            GeometryReader { geo in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.primary.opacity(0.08))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(barColor(for: usage))
                                        .frame(height: max(2, geo.size.height * CGFloat(usage)))
                                }
                            }
                        }
                    }
                    .frame(height: 22)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var networkCard: some View {
        let maxNet = max(
            monitor.downloadHistory.values.max() ?? 0,
            monitor.uploadHistory.values.max() ?? 0,
            10_240
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("网络流量", systemImage: "network")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let iface = monitor.network.activeInterfaceName {
                    Text(iface)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                        Text("下载")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(ByteRateFormatter.detailedRate(monitor.network.downloadBytesPerSec))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.blue)
                        Text("上传")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(ByteRateFormatter.detailedRate(monitor.network.uploadBytesPerSec))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SparklineView(
                series: [
                    SparklineSeries(values: monitor.downloadHistory.values, color: .green, fillOpacity: 0.16),
                    SparklineSeries(values: monitor.uploadHistory.values, color: .blue, fillOpacity: 0.10)
                ],
                maxValue: maxNet
            )
            .frame(height: 52)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Text("本次已收 \(ByteRateFormatter.byteCount(monitor.network.totalReceivedBytes))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text("已发 \(ByteRateFormatter.byteCount(monitor.network.totalSentBytes))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("系统磁盘空间", systemImage: "internaldrive")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("可用 \(ByteRateFormatter.byteCount(monitor.disk.availableBytes))")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(monitor.disk.usedRatio > 0.88 ? .orange : .primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(monitor.disk.usedRatio > 0.88 ? Color.orange : Color.accentColor)
                        .frame(width: max(4, geo.size.width * CGFloat(monitor.disk.usedRatio)))
                }
            }
            .frame(height: 7)

            HStack {
                Text("已用 \(ByteRateFormatter.byteCount(monitor.disk.usedBytes)) / 共 \(ByteRateFormatter.byteCount(monitor.disk.totalBytes))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button(action: onOpenCleaner) {
                    HStack(spacing: 3) {
                        Text("去清理缓存")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.link)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var cpuAccentColor: Color {
        if monitor.cpu.totalUsage >= 0.90 { return .red }
        if monitor.cpu.totalUsage >= 0.75 { return .orange }
        return .accentColor
    }

    private func barColor(for usage: Double) -> Color {
        if usage >= 0.85 { return .red }
        if usage >= 0.65 { return .orange }
        return .accentColor
    }

    private func metricPill(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
    }
}
