import Foundation
import AVKit
import MediaPlayer

/// 用于为 tvOS 原生 AVPlayerViewController 注入视频元数据的工具类
/// （使系统 Transport Bar 自然展示剧集标题、当前集数与大纲）
public enum TVSystemPlayerMetaUtils {
    public static func updateMetadata(
        for item: AVPlayerItem?,
        title: String,
        subtitle: String,
        description: String
    ) {
        guard let item = item else { return }
        var metas: [AVMetadataItem] = []

        if let titleItem = makeItem(.commonIdentifierTitle, value: title) {
            metas.append(titleItem)
        }
        if let subItem = makeItem(.iTunesMetadataTrackSubTitle, value: subtitle) {
            metas.append(subItem)
        }
        if let descItem = makeItem(.commonIdentifierDescription, value: description) {
            metas.append(descItem)
        }

        item.externalMetadata = metas
    }

    private static func makeItem(_ identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem? {
        guard !value.isEmpty else { return nil }
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as? AVMetadataItem
    }
}
