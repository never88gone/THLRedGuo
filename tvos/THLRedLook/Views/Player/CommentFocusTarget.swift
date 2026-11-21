import Foundation

public enum CommentFocusTarget: Hashable {
    case comment(String)
    case reply(String)
    case closeRepliesButton
}
