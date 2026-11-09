import SwiftUI

// MARK: - 数据源诊断与详细信息全链路视图
@MainActor
public struct SourceDiagnosticsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recorder = SourceDiagnostics.shared
    @ObservedObject private var runner = SourceDiagnosticRunner.shared
    @FocusState private var focusedTarget: DiagFocusTarget?
    @State private var showingFullReport = false
    @State private var sharedReport: DiagnosticsShareReport?
    @State private var selectedDetailEntry: SourceDiagnosticEntry? = nil
    @State private var lastSelectedEntryId: UUID? = nil
    @State private var preparingReport = false

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
            Text(SourceDiagnostics.sourceRevision + " · " + recorder.sourceRuntimeStatus)
                .font(.system(size: 25)).foregroundStyle(.secondary)
                .accessibilityIdentifier("sourceDiagnostics.sourceRuntime")
            Text("检测使用当前游客会话，不影响收藏、历史和当前数据源。包含网络DNS、JS引擎、游客会话与剧集解析全链路检测。")
                .font(.system(size: 24)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(recorder.networkEgress?.summary ?? "出口 IP：正在检测…")
                    .font(.system(size: 24, weight: .medium))
                    .accessibilityIdentifier("sourceDiagnostics.egress")
                Text(NetworkEgressResult.notice + " 来源：" + (recorder.networkEgress?.provider ?? "IP.SB / IPWho.is"))
                    .font(.system(size: 20)).foregroundStyle(.secondary)
            }

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
                    preparingReport = true
                    Task {
                        await recorder.refreshNetworkEgress()
                        preparingReport = false
                        showingFullReport = true
                    }
                }
                .disabled(preparingReport)
                .focused($focusedTarget, equals: .action("report"))
                .accessibilityIdentifier("sourceDiagnostics.report")

                TVButton(
                    title: "反馈二维码",
                    icon: "qrcode",
                    isExternalFocused: focusedTarget == .action("qr"),
                    onDownCommand: { focusFirstEntry() }
                ) {
                    preparingReport = true
                    Task {
                        await recorder.refreshNetworkEgress()
                        preparingReport = false
                        sharedReport = DiagnosticsShareReport(text: recorder.report)
                    }
                }
                .disabled(preparingReport)
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
        .task { await recorder.refreshNetworkEgress() }
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
        .sheet(item: $sharedReport, onDismiss: { focusedTarget = .action("qr") }) { report in
            SourceDiagnosticsQRSheet(report: report.text) {
                sharedReport = nil
            }
        }
    }
}
