import Foundation

enum DetailFocus: Hashable {
    case play
    case favorite
    case anchor
    case followState
    case download
    case season(Int)
    case chunk(Int)
    case episode(Int)
}
