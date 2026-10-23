import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - 数据源诊断与详细信息全链路视图
private enum DiagFocusTarget: Hashable {
    case action(String)
    case entry(UUID)
}

@MainActor
public struct SourceDiagnosticsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recorder = SourceDiagnostics.shared
    @ObservedObject private var runner = SourceDiagnosticRunner.shared
    @FocusState private var focusedTarget: DiagFocusTarget?
    @State private var showingQR = false
    @State private var showingFullReport = false
    @State private var reportImage: UIImage?
    @State private var selectedDetailEntry: SourceDiagnosticEntry? = nil
    @State private var lastSelectedEntryId: UUID? = nil

    public init() {}

    private var displayEntries: [SourceDiagnosticEntry] {
        recorder.entries.reversed()
    }

    private func focusFirstEntry() {
        if let first = displayEntries.first {
            focusedTarget = .entry(first.id)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("数据源诊断").font(.system(size: 48, weight: .bold))
            Text("红果官方源 · 应用 \(SourceDiagnostics.version) · 源指纹 \(SourceDiagnostics.sourceHash.prefix(12))")
                .font(.system(size: 29))
            Text("检测使用独立游客会话，不影响收藏、历史和当前数据源。包含网络DNS、JS引擎、游客会话与剧集解析全链路检测。")
                .font(.system(size: 24)).foregroundStyle(.secondary)

            // 操作按钮栏
            HStack(spacing: 24) {
                TVButton(
                    title: runner.running ? "检测中…" : "开始检测",
                    icon: "network",
                    isProminent: true,
                    isExternalFocused: focusedTarget == .action("run"),
                    onDownCommand: { focusFirstEntry() }
                ) {
                    Task { await runner.run() }
                }
                .disabled(runner.running)
                .focused($focusedTarget, equals: .action("run"))
                .accessibilityIdentifier("sourceDiagnostics.run")

                TVButton(
                    title: "详细报告",
                    icon: "doc.text.magnifyingglass",
                    isExternalFocused: focusedTarget == .action("report"),
                    onDownCommand: { focusFirstEntry() }
                ) {
                    showingFullReport = true
                }
                .focused($focusedTarget, equals: .action("report"))
                .accessibilityIdentifier("sourceDiagnostics.report")

                TVButton(
                    title: "反馈二维码",
                    icon: "qrcode",
                    isExternalFocused: focusedTarget == .action("qr"),
                    onDownCommand: { focusFirstEntry() }
                ) {
                    let filter = CIFilter.qrCodeGenerator()
                    filter.message = Data(recorder.qrText.utf8)
                    filter.correctionLevel = "L"
                    if let output = filter.outputImage,
                       let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 4, y: 4)), from: output.extent.applying(CGAffineTransform(scaleX: 4, y: 4))) {
                        reportImage = UIImage(cgImage: image)
                        showingQR = true
                    }
                }
                .focused($focusedTarget, equals: .action("qr"))
                .accessibilityIdentifier("sourceDiagnostics.qr")

                TVButton(
                    title: "清空记录",
                    icon: "trash",
                    isExternalFocused: focusedTarget == .action("clear"),
                    onDownCommand: { focusFirstEntry() }
                ) {
                    recorder.clear()
                }
                .disabled(runner.running)
                .focused($focusedTarget, equals: .action("clear"))
                .accessibilityIdentifier("sourceDiagnostics.clear")

                TVButton(
                    title: "返回",
                    icon: "arrow.backward",
                    isExternalFocused: focusedTarget == .action("back"),
                    onDownCommand: { focusFirstEntry() }
                ) {
                    dismiss()
                }
                .focused($focusedTarget, equals: .action("back"))
                .accessibilityIdentifier("sourceDiagnostics.back")
            }

            // 当前诊断状态汇总
            HStack(spacing: 12) {
                if runner.result.contains("失败") {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.red)
                } else if runner.result.contains("完成") {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.green)
                }
                Text(runner.result)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(runner.result.contains("失败") ? .red : (runner.result.contains("完成") ? .green : .white))
                    .accessibilityIdentifier("sourceDiagnostics.result")
            }

            if runner.running { ProgressView() }

            // 诊断明细流式列表
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if let failure = recorder.entries.last(where: { $0.failed && !$0.host.isEmpty }) {
                            Text("最近失败提示：" + SourceDiagnostics.advice(failure))
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                        }

                        if displayEntries.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "stethoscope")
                                    .font(.system(size: 44))
                                    .foregroundColor(.white.opacity(0.35))
                                Text("暂无诊断记录，请点击上方「开始检测」进行全链路连通性检查。")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(48)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                        } else {
                            ForEach(Array(displayEntries.enumerated()), id: \.element.id) { index, entry in
                                SourceDiagnosticEntryCardView(
                                    entry: entry,
                                    isFocused: focusedTarget == .entry(entry.id),
                                    onSelect: {
                                        lastSelectedEntryId = entry.id
                                        selectedDetailEntry = entry
                                    },
                                    onUpCommand: {
                                        if index == 0 {
                                            focusedTarget = .action("run")
                                        } else {
                                            let prev = displayEntries[index - 1]
                                            focusedTarget = .entry(prev.id)
                                            withAnimation { proxy.scrollTo(prev.id, anchor: .center) }
                                        }
                                    },
                                    onDownCommand: {
                                        if index + 1 < displayEntries.count {
                                            let next = displayEntries[index + 1]
                                            focusedTarget = .entry(next.id)
                                            withAnimation { proxy.scrollTo(next.id, anchor: .center) }
                                        }
                                    }
                                )
                                .focused($focusedTarget, equals: .entry(entry.id))
                                .accessibilityIdentifier("sourceDiagnostics.entry.\(index)")
                                .id(entry.id)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                }
                .focusSection()
                .onChange(of: focusedTarget) { newTarget in
                    if case .entry(let id) = newTarget {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 40)
        .defaultFocus($focusedTarget, .action("run"))
        .onExitCommand { dismiss() }
        .sheet(item: $selectedDetailEntry, onDismiss: {
            if let id = lastSelectedEntryId {
                focusedTarget = .entry(id)
            }
        }) { entry in
            SourceDiagnosticEntryDetailSheet(entry: entry) {
                lastSelectedEntryId = entry.id
                selectedDetailEntry = nil
            }
        }
        .sheet(isPresented: $showingFullReport, onDismiss: { focusedTarget = .action("report") }) {
            SourceDiagnosticsFullReportSheet(reportText: recorder.report) {
                showingFullReport = false
            }
        }
        .sheet(isPresented: $showingQR, onDismiss: { focusedTarget = .action("qr") }) {
            SourceDiagnosticsQRSheet(reportImage: reportImage) {
                showingQR = false
            }
        }
    }
}

@MainActor
private struct SourceDiagnosticEntryCardView: View {
    let entry: SourceDiagnosticEntry
    let isFocused: Bool
    let onSelect: () -> Void
    var onUpCommand: (() -> Void)? = nil
    var onDownCommand: (() -> Void)? = nil

    @Environment(\.isFocused) private var envIsFocused

    private var activeFocused: Bool {
        isFocused || envIsFocused
    }

    private var cardBackground: Color {
        if activeFocused {
            return entry.failed ? Color(red: 0.35, green: 0.12, blue: 0.14) : Color(red: 0.22, green: 0.20, blue: 0.28)
        } else {
            return entry.failed ? Color.red.opacity(0.12) : Color.white.opacity(0.06)
        }
    }

    private var cardBorderColor: Color {
        if activeFocused {
            return Color.white
        } else {
            return entry.failed ? Color.red.opacity(0.4) : Color.white.opacity(0.08)
        }
    }

    private var cardShadowColor: Color {
        guard activeFocused else { return Color.clear }
        return entry.failed ? Color.red.opacity(0.45) : Color.white.opacity(0.3)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                Text(entry.text)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)

                if !entry.errorDetail.isEmpty {
                    errorDetailRow
                }

                if !entry.suggestion.isEmpty {
                    suggestionRow
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(cardBorderColor, lineWidth: activeFocused ? 3.5 : 1)
            )
            .shadow(color: cardShadowColor, radius: activeFocused ? 12 : 0)
            .animation(TVTheme.focusSpringAnimation, value: activeFocused)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .up {
                onUpCommand?()
            } else if direction == .down {
                onDownCommand?()
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            let statusText: String = (entry.failed ? "失败 · " : "完成 · ") + entry.stage
            let statusColor: Color = entry.failed ? Color(red: 1.0, green: 0.35, blue: 0.35) : Color(red: 0.35, green: 0.9, blue: 0.45)
            Text(statusText)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(statusColor)

            if entry.category != .unknown {
                let badgeBg: Color = entry.failed ? Color.red.opacity(0.85) : Color.blue.opacity(0.8)
                Text(entry.category.tag)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeBg)
                    .clipShape(Capsule())
            }

            if entry.elapsedMs > 0 {
                Text("\(entry.elapsedMs)ms")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 详细信息操作指示
            HStack(spacing: 6) {
                Text("详细信息")
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(activeFocused ? .white : .white.opacity(0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(activeFocused ? TVTheme.primary : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
    }

    private var errorDetailRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("失败原因:")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.orange)
            Text(entry.errorDetail)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(.orange.opacity(0.95))
        }
    }

    private var suggestionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("排查建议:")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(TVTheme.primaryHover)
            Text(entry.suggestion)
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - 单项诊断技术详细信息弹窗 (支持长文本遥控器滚动与参数网格)
@MainActor
private struct SourceDiagnosticEntryDetailSheet: View {
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
            // 顶部导航与关闭
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

            // 中间可滚动详情内容
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    // 状态横幅卡片
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

                    // 核心参数网格卡片
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

                    // 失败具体原因
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

                    // 排查建议
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

                    // 原始摘要信息
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

@MainActor
private struct SourceDiagnosticsFullReportSheet: View {
    let reportText: String
    let onClose: () -> Void

    @FocusState private var focusedField: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("完整技术诊断报告")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                    Text("包含环境指纹、各链路分段耗时与详细错误堆栈，可供技术排查与社区求助")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
                TVButton(
                    title: "关闭报告",
                    icon: "xmark.circle.fill",
                    isProminent: true,
                    onDownCommand: {
                        focusedField = "content"
                    }
                ) {
                    onClose()
                }
                .focused($focusedField, equals: "close")
                .accessibilityIdentifier("sourceDiagnostics.reportClose")
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(reportText)
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .lineSpacing(6)
                        .foregroundColor(.white.opacity(0.95))
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(focusedField == "content" ? Color.white : Color.white.opacity(0.12), lineWidth: focusedField == "content" ? 3.5 : 1)
                        )
                        .shadow(color: focusedField == "content" ? Color.white.opacity(0.3) : Color.clear, radius: 8)
                        .focusable()
                        .focused($focusedField, equals: "content")
                        .accessibilityIdentifier("sourceDiagnostics.reportContent")
                        .onMoveCommand { direction in
                            if direction == .up {
                                focusedField = "close"
                            }
                        }
                }
                .padding(8)
            }
            .focusSection()
        }
        .padding(48)
        .defaultFocus($focusedField, "close")
        .onExitCommand { onClose() }
    }
}

@MainActor
private struct SourceDiagnosticsQRSheet: View {
    let reportImage: UIImage?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("扫码获取诊断报告").font(.system(size: 42, weight: .bold))
            if let reportImage {
                Image(uiImage: reportImage).interpolation(.none).resizable()
                    .scaledToFit().frame(width: 500, height: 500)
                    .padding(24).background(.white)
            }
            Text("包含版本、源指纹和最多最近 8 条脱敏记录。扫码读取文本后手动反馈，不会自动上传。")
                .font(.system(size: 29)).multilineTextAlignment(.center)
            TVButton(title: "返回诊断", icon: "arrow.backward", isProminent: true) { onClose() }
                .accessibilityIdentifier("sourceDiagnostics.qrBack")
        }
        .padding(60)
        .onExitCommand { onClose() }
    }
}
