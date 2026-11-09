import Foundation

struct HongguoSocialSnapshot {
    let episodes: [HongguoEpisodeLike]
    let creators: [HongguoCreator]
    var creatorError: String? = nil
    func episode(_ number: Int) -> HongguoEpisodeLike? { episodes.first { $0.number == number } }
}
