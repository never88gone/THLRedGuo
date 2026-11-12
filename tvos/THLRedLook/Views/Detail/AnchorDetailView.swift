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
    @FocusState private var actionFocus: String?

    public init(anchor: Anchor, relatedDrama: Drama? = nil) {
        initialAnchor = anchor; self.relatedDrama = relatedDrama; profileRequest = nil; allowsWrites = true; onFollowingChanged = nil
    }

    init(anchor: Anchor, profileRequest: @escaping (String) async throws -> Anchor, allowsWrites: Bool, onFollowingChanged: (() -> Void)? = nil) {
        initialAnchor = anchor; relatedDrama = nil; self.profileRequest = profileRequest; self.allowsWrites = allowsWrites; self.onFollowingChanged = onFollowingChanged
    }

    public var body: some View {
        ZStack {
            TVColors.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                if let anchor {
                    AnchorHeaderView(anchor: anchor, isFollowed: anchor.following == true,
                        followEnabled: allowsWrites && !loading && !writing && anchor.following != nil && (anchor.canFollow == true || anchor.following == true),
                        onToggleFollow: { Task { await toggleFollow(anchor) } }, onBack: { dismiss() })
                } else {
                    Button("返回") { dismiss() }.focused($actionFocus, equals: "back").accessibilityIdentifier("anchor.back")
                }
                if loading || writing { ProgressView(writing ? "正在确认关注状态" : "正在获取主播资料").accessibilityIdentifier("anchor.loading") }
                if let error {
                    Text(error).foregroundStyle(.orange).accessibilityIdentifier("anchor.error")
                    Button("重试") { Task { await load() } }.disabled(loading || writing)
                        .focused($actionFocus, equals: "retry").accessibilityIdentifier("anchor.retry")
                }
                if let anchor {
                    AnchorDramaGridView(dramas: anchor.dramas, onSelectDrama: { selectedDrama = $0 })
                }
                Spacer(minLength: 0)
            }
        }
        .fullScreenCover(item: $selectedDrama, onDismiss: { detailDismissedAt = Date() }) { DramaDetailView(drama: $0) }
        .task(id: HongguoAccountVault.shared.snapshot.revision) { anchor = nil; await load() }
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
        } catch {
            guard ticket == generation, revision == HongguoAccountVault.shared.snapshot.revision else { return }
            self.error = error.localizedDescription
            actionFocus = "retry"
        }
        if ticket == generation { loading = false }
    }

    private func toggleFollow(_ current: Anchor) async {
        guard !writing, let following = current.following else { return }
        let revision = HongguoAccountVault.shared.snapshot.revision
        writing = true; error = nil
        do {
            try await account.setProfileFollowing(current, follow: !following)
            guard revision == HongguoAccountVault.shared.snapshot.revision else { return }
            onFollowingChanged?()
            await load()
        } catch {
            if revision == HongguoAccountVault.shared.snapshot.revision { self.error = error.localizedDescription }
        }
        writing = false
    }
}
