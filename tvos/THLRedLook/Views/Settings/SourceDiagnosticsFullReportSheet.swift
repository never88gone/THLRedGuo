import SwiftUI

@MainActor
struct SourceDiagnosticsFullReportSheet: View {
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
