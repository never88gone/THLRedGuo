import SwiftUI

/// 主播作品短剧网格展示组件
public struct AnchorDramaGridView: View {
    public let dramas: [Drama]
    public let onSelectDrama: (Drama) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 28), count: 5)
    private let focus: FocusState<AnchorHeaderFocus?>.Binding
    private let onUpCommand: () -> Void

    public init(dramas: [Drama], focus: FocusState<AnchorHeaderFocus?>.Binding, onSelectDrama: @escaping (Drama) -> Void, onUpCommand: @escaping () -> Void) {
        self.dramas = dramas
        self.onSelectDrama = onSelectDrama
        self.focus = focus
        self.onUpCommand = onUpCommand
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
                        ForEach(dramas) { drama in
                            DramaCardView(
                                drama: drama,
                                isFocused: focus.wrappedValue == .drama(drama.id),
                                onUpCommand: dramas.prefix(columns.count).contains(where: { $0.id == drama.id }) ? onUpCommand : nil
                            ) {
                                onSelectDrama(drama)
                            }
                            .focused(focus, equals: .drama(drama.id))
                            .accessibilityIdentifier("anchor.drama.\(drama.id)")
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 60)
                }
            }
        }
    }
}
