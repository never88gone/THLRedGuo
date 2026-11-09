import SwiftUI

public struct JSSourcePluginCard: View {
    public let id: String
    public let name: String
    public let version: String
    public let author: String
    public let isActive: Bool
    public let onSelect: () -> Void
    public let onRemove: () -> Void

    @FocusState private var isCardFocused: Bool
    @FocusState private var isTrashFocused: Bool
    @State private var showDeleteConfirm = false

    public init(
        id: String,
        name: String,
        version: String,
        author: String,
        isActive: Bool,
        onSelect: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.isActive = isActive
        self.onSelect = onSelect
        self.onRemove = onRemove
    }

    private var isBuiltIn: Bool {
        id.lowercased() == "hongguo"
    }

    public var body: some View {
        HStack(spacing: 14) {
            // 左侧：切换选择按钮
            Button(action: onSelect) {
                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(isActive ? TVTheme.primary.opacity(0.25) : TVColors.sourceCardIconBg)
                            .frame(width: 52, height: 52)
                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 26))
                            .foregroundColor(isActive ? TVTheme.primary : Color.white.opacity(0.45))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text(name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            if isActive {
                                Text("当前活跃源")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(TVTheme.primary)
                                    .clipShape(Capsule())
                            }
                            if isBuiltIn {
                                Text("官方内置")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("v\(version) · 作者: \(author) · 脚本: \(id).js")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isCardFocused ? TVTheme.primary : Color.white.opacity(0.3))
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            isCardFocused
                                ? TVColors.sourceCardFocused
                                : (isActive ? TVColors.sourceCardActive : TVColors.sourceCardInactive)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            isCardFocused
                                ? Color.white
                                : (isActive ? TVTheme.primary.opacity(0.55) : Color.white.opacity(0.06)),
                            lineWidth: isCardFocused ? 3.0 : (isActive ? 1.5 : 1.0)
                        )
                )
                .scaleEffect(isCardFocused ? 1.02 : 1.0)
                .shadow(
                    color: isCardFocused ? TVTheme.primary.opacity(0.5) : Color.clear,
                    radius: isCardFocused ? 14 : 0,
                    x: 0,
                    y: isCardFocused ? 4 : 0
                )
                .animation(TVTheme.focusSpringAnimation, value: isCardFocused)
                .tvFocusBorder(isFocused: isCardFocused, cornerRadius: 18)
            }
            .buttonStyle(TVZeroHighlightButtonStyle())
            .focused($isCardFocused)
            .focusEffectDisabled()
            .accessibilityIdentifier("settings.source.card.\(id)")
            .contextMenu {
                Button {
                    onSelect()
                } label: {
                    Label("激活此数据源", systemImage: "checkmark.circle")
                }
                if !isBuiltIn {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除此数据源", systemImage: "trash")
                    }
                }
            }

            // 右侧：自定义数据源独立删除按钮（支持遥控器向右切换焦点选中）
            if !isBuiltIn {
                Button(action: {
                    showDeleteConfirm = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(isTrashFocused ? .white : .red.opacity(0.85))
                        Text("删除")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isTrashFocused ? .white : .red.opacity(0.75))
                    }
                    .frame(width: 80, height: 86)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(isTrashFocused ? TVColors.sourceDeleteFocusedBg : TVColors.sourceDeleteBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isTrashFocused ? Color.white : TVColors.sourceDeleteBorder, lineWidth: isTrashFocused ? 3 : 1)
                    )
                    .tvFocusBorder(isFocused: isTrashFocused, cornerRadius: 18)
                }
                .buttonStyle(TVZeroHighlightButtonStyle())
                .focused($isTrashFocused)
                .focusEffectDisabled()
                .accessibilityIdentifier("settings.source.delete.\(id)")
                .alert("删除数据源", isPresented: $showDeleteConfirm) {
                    Button("取消", role: .cancel) {}
                    Button("确认删除", role: .destructive) {
                        onRemove()
                    }
                } message: {
                    Text("确定要删除数据源「\(name)」(\(id).js) 吗？删除后本地文件将被彻底移除。")
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}
