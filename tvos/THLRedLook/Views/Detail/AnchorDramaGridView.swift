import SwiftUI

/// 主播作品短剧网格展示组件
public struct AnchorDramaGridView: View {
    public let dramas: [Drama]
    public let onSelectDrama: (Drama) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 28), count: 5)
    private let focus: FocusState<AnchorHeaderFocus?>.Binding
    private let onUpCommand: () -> Void
    private let onReachEnd: (() -> Void)?
    private let loadingMore: Bool

    public init(
        dramas: [Drama],
        focus: FocusState<AnchorHeaderFocus?>.Binding,
        loadingMore: Bool = false,
        onSelectDrama: @escaping (Drama) -> Void,
        onUpCommand: @escaping () -> Void,
        onReachEnd: (() -> Void)? = nil
    ) {
        self.dramas = dramas
        self.loadingMore = loadingMore
        self.onSelectDrama = onSelectDrama
        self.focus = focus
        self.onUpCommand = onUpCommand
        self.onReachEnd = onReachEnd
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("关联短剧")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(TVColors.textPrimary)
                .padding(.horizontal, 60)

            if dramas.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "film")
                        .font(.system(size: 48))
                        .foregroundColor(TVColors.textMuted)
                    Text("暂无可展示的关联短剧")
                        .font(.system(size: 22))
                        .foregroundColor(TVColors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 36) {
                        ForEach(Array(dramas.enumerated()), id: \.element.id) { index, drama in
                            DramaCardView(
                                drama: drama,
                                isFocused: focus.wrappedValue == .drama(drama.id),
                                onUpCommand: index < columns.count ? onUpCommand : nil
                            ) {
                                onSelectDrama(drama)
                            }
                            .focused(focus, equals: .drama(drama.id))
                            .accessibilityIdentifier("anchor.drama.\(drama.id)")
                            .onAppear {
                                if index >= max(0, dramas.count - 5) {
                                    onReachEnd?()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 28)
                    .padding(.bottom, loadingMore ? 16 : 60)
                    if loadingMore {
                        ProgressView("正在加载更多作品")
                            .padding(.bottom, 48)
                    }
                }
            }
        }
    }
}
