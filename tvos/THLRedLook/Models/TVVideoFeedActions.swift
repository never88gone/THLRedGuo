import Foundation

public struct TVVideoFeedActions {
    public let progressText: String
    public let canGoPrevious: Bool
    public let canGoNext: Bool
    public let isLoading: Bool
    public let isFavorite: Bool
    public let errorMessage: String?
    public let onPrevious: () -> Void
    public let onNext: () async -> Bool
    public let onFavorite: () -> Void
    public let onDetail: (Drama) -> Void
    public let onRefresh: () -> Void

    public init(
        progressText: String,
        canGoPrevious: Bool,
        canGoNext: Bool,
        isLoading: Bool,
        isFavorite: Bool,
        errorMessage: String?,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () async -> Bool,
        onFavorite: @escaping () -> Void,
        onDetail: @escaping (Drama) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.progressText = progressText
        self.canGoPrevious = canGoPrevious
        self.canGoNext = canGoNext
        self.isLoading = isLoading
        self.isFavorite = isFavorite
        self.errorMessage = errorMessage
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onFavorite = onFavorite
        self.onDetail = onDetail
        self.onRefresh = onRefresh
    }
}
