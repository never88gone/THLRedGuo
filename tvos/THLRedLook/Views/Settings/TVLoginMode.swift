import Foundation

// MARK: - 电视大屏扫码登录模式定义
public enum TVLoginMode: String, CaseIterable, Identifiable {
    case officialQR = "officialQR"
    case hawQR = "hawQR"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .officialQR: return "红果 App 扫码"
        case .hawQR: return "手机 Haw 扫码"
        }
    }

    public var subtitle: String {
        switch self {
        case .officialQR: return "官方推荐 · 手机红果扫一扫"
        case .hawQR: return "同一局域网内手机 Haw 快速授权"
        }
    }

    public var icon: String {
        switch self {
        case .officialQR: return "qrcode.viewfinder"
        case .hawQR: return "iphone.and.arrow.forward"
        }
    }
}
