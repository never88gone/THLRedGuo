import Foundation
import AVFoundation

public struct PreparedPlaybackAsset {
    public let asset: AVURLAsset
    public let decryptedURL: URL?

    public init(asset: AVURLAsset, decryptedURL: URL?) {
        self.asset = asset
        self.decryptedURL = decryptedURL
    }
}
