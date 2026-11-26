import SwiftUI

// MARK: - 视频控制设置面板
public struct SettingsPlaybackControlPanel: View {
    @ObservedObject private var store = LocalStore.shared
    @State private var noticeMessage: String? = nil

    public struct RateItem: Identifiable {
        public let rate: Double
        public let label: String
        public var id: Double { rate }
    }

    public let items: [RateItem] = [
        RateItem(rate: 0.75, label: "0.75x 慢速"),
        RateItem(rate: 1.0, label: "1.0x 标准"),
        RateItem(rate: 1.25, label: "1.25x 轻快"),
        RateItem(rate: 1.5, label: "1.5x 快速"),
        RateItem(rate: 2.0, label: "2.0x 超速")
    ]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            headerView
            if let msg = noticeMessage {
                noticeView(text: msg)
            }
            rateCardView
            tipsView
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("视频控制")
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(TVColors.white)
            Text("配置电视大屏端默认播放速率与起播偏好，设定后进入视频将默认生效。")
                .font(.system(size: 20))
                .foregroundColor(TVColors.white.opacity(0.6))
        }
    }

    private func noticeView(text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(TVColors.green)
            Text(text)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(TVColors.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(TVColors.green.opacity(0.2))
        .cornerRadius(12)
    }

    private var rateCardView: some View {
        VStack(alignment: .leading, spacing: 20) {
            rateCardHeader
            rateCardDescription
            rateButtonsRow
        }
        .padding(24)
        .background(TVColors.surfaceCard.opacity(0.75))
        .cornerRadius(20)
    }

    private var rateCardHeader: some View {
        HStack {
            Text("默认视频播放速率")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(TVColors.white)
            Spacer()
            Text("当前设置: \(formattedRate)")
                .font(.system(size: 16))
                .foregroundColor(TVColors.white.opacity(0.7))
        }
    }

    private var rateCardDescription: some View {
        Text("选择进入视频播放后默认使用的起播倍速。设定后无论从剧集详情、推荐流或离线列表起播，均以此速率播放。")
            .font(.system(size: 16))
            .foregroundColor(TVColors.white.opacity(0.55))
    }

    private var rateButtonsRow: some View {
        HStack(spacing: 16) {
            ForEach(items) { item in
                PlaybackRateButton(
                    item: item,
                    isSelected: isRateSelected(item.rate)
                ) {
                    selectRate(item.rate, title: item.label)
                }
            }
        }
    }

    private func isRateSelected(_ rate: Double) -> Bool {
        abs(store.defaultPlaybackRate - rate) < 0.05
    }

    private var formattedRate: String {
        let r = store.defaultPlaybackRate
        if abs(r - 1.0) < 0.05 {
            return "1.0x (标准)"
        }
        return String(format: "%.2fx", r).replacingOccurrences(of: ".00", with: ".0")
    }

    private func selectRate(_ rate: Double, title: String) {
        store.setDefaultPlaybackRate(rate)
        withAnimation {
            noticeMessage = "已设为 \(title)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                noticeMessage = nil
            }
        }
    }

    private var tipsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("使用说明")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(TVColors.white.opacity(0.9))
            Text("• 全场景生效：无论是从首页分类选剧、搜索结果、排行榜，还是离线下载列表中点击播放，均自动以您设置的默认速率起播。\n• 临时调速：播放中仍可随时按遥控器向下呼出倍速抽屉临时切换速率，不影响全局默认偏好。")
                .font(.system(size: 16))
                .foregroundColor(TVColors.white.opacity(0.6))
                .lineSpacing(6)
        }
        .padding(20)
        .background(TVColors.white.opacity(0.04))
        .cornerRadius(14)
    }
}

// MARK: - 倍速选项按钮组件
private struct PlaybackRateButton: View {
    let item: SettingsPlaybackControlPanel.RateItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        TVButton(
            title: item.label,
            icon: isSelected ? "checkmark" : nil,
            isProminent: isSelected,
            accessibilityID: "settings.playback.rate.\(item.rate)"
        ) {
            onSelect()
        }
    }
}

#Preview {
    ZStack {
        TVColors.background.ignoresSafeArea()
        SettingsPlaybackControlPanel()
            .padding(40)
    }
}
