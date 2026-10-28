import SwiftUI

public struct TVQualitySelectionDrawer: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isPresented: Bool
    @FocusState private var focusedQuality: Int?

    public var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Text("播放清晰度").font(.system(size: 42, weight: .bold))
                Text("当前播放：" + PlaybackPlan.qualityLabel(viewModel.selectedQuality))
                    .font(.system(size: 27)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("player.quality.current")
                Text("按 Menu 返回").font(.system(size: 25)).foregroundStyle(.secondary)
                Divider()
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(viewModel.qualityOptions, id: \.self) { quality in
                            let selected = quality == viewModel.requestedQuality
                            let focused = quality == focusedQuality
                            Button {
                                viewModel.restoreFocusTarget = .quality
                                isPresented = false
                                Task { await viewModel.changeQuality(quality) }
                            } label: {
                                HStack {
                                    Text(quality == 0 ? "自动（优先 1080P）" : PlaybackPlan.qualityLabel(quality))
                                        .font(.system(size: 29, weight: .bold))
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill").opacity(selected ? 1 : 0)
                                }
                                .padding(.horizontal, 24).padding(.vertical, 18)
                                .foregroundStyle(TVTheme.textPrimary)
                                .background(RoundedRectangle(cornerRadius: 14).fill(selected ? (focused ? TVTheme.primaryHover : TVTheme.primary) : (focused ? TVTheme.surfaceFocused : TVTheme.surfaceCard)))
                                .tvFocusBorder(isFocused: focused, cornerRadius: 14)
                            }
                            .buttonStyle(TVZeroHighlightButtonStyle())
                            .focused($focusedQuality, equals: quality)
                            .accessibilityIdentifier("player.quality.option.\(quality)")
                            .focusEffectDisabled()
                        }
                    }.padding(6)
                }
                .scrollClipDisabled()
            }
            .padding(.horizontal, 40).padding(.vertical, 60)
            .frame(width: 680).frame(maxHeight: .infinity)
            .background(Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.96))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea()
        .onExitCommand {
            viewModel.restoreFocusTarget = .quality
            isPresented = false
        }
        .task {
            focusedQuality = viewModel.qualityOptions.contains(viewModel.requestedQuality) ? viewModel.requestedQuality : 0
        }
    }
}
