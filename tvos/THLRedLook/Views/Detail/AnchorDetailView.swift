import SwiftUI

public struct AnchorDetailView: View {
    @ObservedObject private var account = HongguoAccountModel.shared
    @Environment(\.dismiss) private var dismiss
    public let initialAnchor: Anchor
    public let relatedDrama: Drama?
    private let profileRequest: ((String) async throws -> Anchor)?
    private let allowsWrites: Bool
    private let onFollowingChanged: (() -> Void)?
    @State private var anchor: Anchor?
    @State private var selectedDrama: Drama?
    @State private var error: String?
    @State private var loading = false
    @State private var writing = false
    @State private var generation = 0
    @State private var detailDismissedAt = Date.distantPast
    @FocusState private var actionFocus: AnchorHeaderFocus?
    @State private var lastDramaID: String?
    @State private var loadedRevision: UInt64?

    public init(anchor: Anchor, relatedDrama: Drama? = nil) {
        initialAnchor = anchor; self.relatedDrama = relatedDrama; profileRequest = nil; allowsWrites = true; onFollowingChanged = nil
    }

    init(anchor: Anchor, profileRequest: @escaping (String) async throws -> Anchor, allowsWrites: Bool, onFollowingChanged: (() -> Void)? = nil) {
        initialAnchor = anchor; relatedDrama = nil; self.profileRequest = profileRequest; self.allowsWrites = allowsWrites; self.onFollowingChanged = onFollowingChanged
    }

    private var followEnabled: Bool {
        guard account.loggedIn, let anchor else { return false }
        return allowsWrites && !loading && !writing && anchor.following != nil && (anchor.canFollow == true || anchor.following == true)
    }

    private var dramaFocus: AnchorHeaderFocus? {
        let dramas = anchor?.dramas ?? []
        if let id = lastDramaID, dramas.contains(where: { $0.id == id }) { return .drama(id) }
        return dramas.first.map { .drama($0.id) }
    }

    public var body: some View {
        ZStack {
            TVColors.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                if let anchor {
                    AnchorHeaderView(
                        anchor: anchor,
                        isFollowed: anchor.following == true,
                        followEnabled: followEnabled,
                        focus: $actionFocus,
                        onToggleFollow: { Task { await toggleFollow(anchor) } },
                        onDownCommand: { actionFocus = error == nil ? dramaFocus : .retry }
                    )
                }
                if loading || writing { ProgressView(writing ? "正在确认关注状态" : "正在获取主播资料").accessibilityIdentifier("anchor.loading") }
                if let error {
                    Text(error).foregroundStyle(.orange).accessibilityIdentifier("anchor.error")
                    Button("重试") { Task { await load() } }.disabled(loading || writing)
                        .focused($actionFocus, equals: .retry).accessibilityIdentifier("anchor.retry")
                        .onMoveCommand { direction in
                            if direction == .up && followEnabled { actionFocus = .follow }
                            if direction == .down { actionFocus = dramaFocus }
                        }
                }
                if let anchor {
                    AnchorDramaGridView(dramas: anchor.dramas, focus: $actionFocus, onSelectDrama: {
                        lastDramaID = $0.id; selectedDrama = $0
                    }, onUpCommand: {
                        if error != nil { actionFocus = .retry }
                        else if followEnabled { actionFocus = .follow }
                    })
                }
                Spacer(minLength: 0)
            }
        }
        .defaultFocus($actionFocus, followEnabled ? .follow : dramaFocus)
        .fullScreenCover(item: $selectedDrama, onDismiss: {
            detailDismissedAt = Date()
            DispatchQueue.main.async { actionFocus = dramaFocus }
        }) { DramaDetailView(drama: $0) }
        .task(id: HongguoAccountVault.shared.snapshot.revision) {
            if loadedRevision != HongguoAccountVault.shared.snapshot.revision { anchor = nil; await load() }
        }
        .onDisappear { generation += 1 }
        .onExitCommand {
            guard selectedDrama == nil, Date().timeIntervalSince(detailDismissedAt) > 0.5 else { return }
            dismiss()
        }
    }

    private func load() async {
        generation += 1; let ticket = generation
        let revision = HongguoAccountVault.shared.snapshot.revision
        loading = true; error = nil
        do {
            let dramas = relatedDrama.map { [$0] } ?? initialAnchor.dramas
            let result: Anchor
            if let profileRequest { result = try await profileRequest(initialAnchor.id) }
            else { result = try await AnchorService.shared.fetchAnchorDetail(anchorId: initialAnchor.id, dramas: dramas) }
            guard ticket == generation, revision == HongguoAccountVault.shared.snapshot.revision else { return }
            anchor = result
            loadedRevision = revision
        } catch {
            guard ticket == generation, revision == HongguoAccountVault.shared.snapshot.revision else { return }
            self.error = error.localizedDescription
            actionFocus = .retry
        }
        if ticket == generation { loading = false }
    }

    private func toggleFollow(_ current: Anchor) async {
        guard account.loggedIn, !writing, let following = current.following else { return }
        writing = true; error = nil
        let next = !following
        let updated = Anchor(
            id: current.id,
            name: current.name,
            avatar: current.avatar,
            intro: current.intro,
            followerCount: current.followerCount.map { max(0, $0 + (next ? 1 : -1)) } ?? (next ? 1 : 0),
            worksCount: current.worksCount,
            dramas: current.dramas,
            following: next,
            canFollow: true,
            relativeType: current.relativeType
        )
        self.anchor = updated
        onFollowingChanged?()

        do {
            try await account.setProfileFollowing(current, follow: next)
        } catch {
            NSLog("🎬 [AnchorDetailView] 接口请求关注: %@", error.localizedDescription)
        }
        writing = false
    }
}
