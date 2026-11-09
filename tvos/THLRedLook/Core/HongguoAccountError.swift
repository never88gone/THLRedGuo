import Foundation

enum HongguoAccountError: LocalizedError, Equatable {
    case cancelled, storage, invalid, expired, challenge, followSecurity, writeNotConfirmed, interactionInvalid, server(Int), business(Int), preparation(String), network
    var errorDescription: String? {
        switch self {
        case .cancelled: return "账号操作已取消"
        case .interactionInvalid: return "官方互动数据暂不可用，请刷新后重试"
        case .writeNotConfirmed: return "官方互动状态尚未确认，请刷新后重试"
        case .storage: return "账号安全存储暂不可用，请重试"
        case .invalid: return "账号校验失败，请重新扫码或稍后重试"
        case .expired: return "二维码已过期，请刷新"
        case .challenge: return "红果要求额外安全验证，请使用红果 App 扫码登录"
        case .followSecurity: return "红果安全校验未通过（103012），请稍后重试"
        case .server(let status): return "账号请求失败（HTTP \(status)）"
        case .business(let code): return "官方账号请求失败（错误码 \(code)）"
        case .preparation(let code): return "账号请求准备失败（\(code)）"
        case .network: return "账号网络请求失败，请稍后重试"
        }
    }
}
