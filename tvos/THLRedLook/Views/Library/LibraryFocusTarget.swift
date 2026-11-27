import Foundation

public enum LibraryFocusTarget: Hashable {
    case mainTab(LibraryTab)
    case followFilter(FollowState)
    case reservationFilter(Bool)
    case clearHistory
    case account
    case refresh
    case loadMore
    case card(String)
    case anchorCard(String)
    case emptyAction
}
