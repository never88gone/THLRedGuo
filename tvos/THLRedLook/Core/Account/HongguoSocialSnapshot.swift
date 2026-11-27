import Foundation

struct HongguoSocialSnapshot {
    let episodes: [HongguoEpisodeLike]
    let creators: [HongguoCreator]
    var creatorError: String? = nil
    var onlineSubscribed: Bool = false
    var isOnline: Bool = true
    func episode(_ number: Int) -> HongguoEpisodeLike? { episodes.first { $0.number == number } }
}
