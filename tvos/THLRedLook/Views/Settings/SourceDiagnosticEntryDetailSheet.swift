import SwiftUI

@MainActor
struct SourceDiagnosticEntryDetailSheet: View {
    let entry: SourceDiagnosticEntry
    let onClose: () -> Void

    @FocusState private var focusedTarget: String?

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: entry.at)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                HStack(spacing: 16) {
                    Image(systemName: entry.failed ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 38))
                        .foregroundColor(entry.failed ? .red : .green)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Text("诊断项详细信息")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundColor(.white)
                            if entry.category != .unknown {
                                Text(entry.category.tag)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(entry.failed ? Color.red.opacity(0.85) : Color.blue.opacity(0.8))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("探测阶段: \(entry.stage) · 检测时间: \(formattedDate)")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }

                Spacer()

                TVButton(
                    title: "关闭详情",
                    icon: "xmark.circle.fill",
                    isProminent: true,
                    onDownCommand: {
                        focusedTarget = "scrollable"
                    }
                ) {
                    onClose()
                }
                .focused($focusedTarget, equals: "close")
                .accessibilityIdentifier("sourceDiagnostics.detailClose")
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 24) {
                        detailStatusPill(
                            title: "状态",
                            value: entry.failed ? "探测失败" : "探测成功",
                            color: entry.failed ? .red : .green
                        )
                        detailStatusPill(
                            title: "响应耗时",
                            value: entry.elapsedMs > 0 ? "\(entry.elapsedMs) ms" : "< 1 ms",
                            color: entry.elapsedMs > 1000 ? .orange : .blue
                        )
                        if entry.status > 0 {
                            detailStatusPill(
                                title: "HTTP 状态码",
                                value: "\(entry.status)",
                                color: entry.status == 200 ? .green : .red
                            )
                        }
                        if !entry.businessCode.isEmpty {
                            detailStatusPill(
                                title: "业务返回码",
                                value: entry.businessCode,
                                color: entry.businessCode == "0" ? .green : .orange
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("探测参数与链路环境")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            infoRow(label: "探测阶段", value: entry.stage)
                            infoRow(label: "执行上下文", value: entry.context)
                            infoRow(label: "目标主机", value: entry.host.isEmpty ? "本地执行 (无主机)" : entry.host)
                            infoRow(label: "故障分类", value: entry.category.name)
                            if !entry.errorCode.isEmpty {
                                infoRow(label: "错误特征代码", value: entry.errorCode)
                            }
                            if let count = entry.count {
                                infoRow(label: "返回数据条数", value: "\(count) 条")
                            }
                        }
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

                    if !entry.errorDetail.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                                Text("失败具体原因与技术诊断")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            Text(entry.errorDetail)
                                .font(.system(size: 20, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.15))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.35), lineWidth: 1))
                                .cornerRadius(12)
                                .accessibilityIdentifier("sourceDiagnostics.detailError")
                        }
                        .padding(24)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }

                    if !entry.suggestion.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(TVTheme.primaryHover)
                                Text("排查建议与修复措施")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(TVTheme.primaryHover)
                            }
                            Text(entry.suggestion)
                                .font(.system(size: 22))
                                .foregroundColor(.white.opacity(0.95))
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(TVTheme.primary.opacity(0.15))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(TVTheme.primary.opacity(0.35), lineWidth: 1))
                                .cornerRadius(12)
                                .accessibilityIdentifier("sourceDiagnostics.detailSuggestion")
                        }
                        .padding(24)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }

                    if !entry.url.isEmpty || !entry.logId.isEmpty || !entry.searchTabsSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "network.badge.shield.half.filled")
                                    .foregroundColor(.cyan)
                                Text("网络链路与请求追踪")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.cyan)
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                if !entry.method.isEmpty {
                                    infoRow(label: "HTTP 方法", value: entry.method)
                                }
                                if !entry.logId.isEmpty {
                                    infoRow(label: "字节 LogID", value: entry.logId)
                                }
                                if !entry.sessionStatus.isEmpty {
                                    infoRow(label: "会话状态", value: entry.sessionStatus)
                                }
                                if !entry.searchTabsSummary.isEmpty {
                                    infoRow(label: "分类分布", value: entry.searchTabsSummary)
                                }
                            }

                            if !entry.url.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("脱敏请求 URL:")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                    Text(entry.url)
                                        .font(.system(size: 16, design: .monospaced))
                                        .foregroundColor(.cyan)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.35))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(24)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }

                    if !entry.responseSnippet.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "curlybraces")
                                    .foregroundColor(.yellow)
                                Text("脱敏响应结构摘要")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.yellow)
                            }
                            Text(entry.responseSnippet)
                                .font(.system(size: 16, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.55))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
                                .cornerRadius(12)
                        }
                        .padding(24)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("原始摘要信息")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        Text(entry.text)
                            .font(.system(size: 18, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(12)
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(12)
                .focusable()
                .focused($focusedTarget, equals: "scrollable")
                .onMoveCommand { direction in
                    if direction == .up {
                        focusedTarget = "close"
                    }
                }
            }
            .focusSection()
        }
        .padding(48)
        .defaultFocus($focusedTarget, "close")
        .onExitCommand { onClose() }
    }

    private func detailStatusPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(color.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.35), lineWidth: 1))
        .cornerRadius(14)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label + ":")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
        }
    }
}
