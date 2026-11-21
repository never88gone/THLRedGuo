import Foundation

// MARK: - 红果账号创作者与社交互动远端请求服务
@MainActor
final class HongguoAccountSocialService {
    private let transportService: HongguoAccountTransport
    private let vault: HongguoAccountVault
    private var collectionIdentity: (revision: UInt64, id: String)?

    init(transportService: HongguoAccountTransport, vault: HongguoAccountVault) {
        self.transportService = transportService
        self.vault = vault
    }

    func resetIdentity() {
        collectionIdentity = nil
    }

    func readCollection(
        _ action: String,
        payload: [String: String],
        loggedIn: Bool,
        attempt: Int,
        account: HongguoAccountRecord?
    ) async throws -> [String: Any] {
        guard loggedIn else { throw HongguoAccountError.invalid }
        let revision = vault.snapshot.revision
        let result = try await transportService.call(
            action,
            payload: payload,
            owner: attempt,
            attempt: attempt,
            existing: true,
            account: account,
            cookies: []
        ).result
        guard vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        return result
    }

    func creatorProfile(
        _ id: String,
        dramas: [Drama] = [],
        loggedIn: Bool,
        attempt: Int,
        account: HongguoAccountRecord?
    ) async throws -> Anchor {
        let result = try await readCollection(
            "creatorProfile",
            payload: ["userId": id],
            loggedIn: loggedIn,
            attempt: attempt,
            account: account
        )
        guard let row = result["creator"] as? [String: Any],
              row["id"] as? String == id || row["businessId"] as? String == id,
              let anchor = Anchor(official: row, dramas: dramas) else {
            throw HongguoAccountError.interactionInvalid
        }
        return anchor
    }

    func creatorWorks(
        _ id: String,
        cursor: String = "",
        count: Int = 20,
        commentSource: Int = 1506,
        tabType: Int = 23,
        loggedIn: Bool,
        attempt: Int,
        account: HongguoAccountRecord?
    ) async throws -> (items: [Drama], hasMore: Bool, nextCursor: String, commentSource: Int, tabType: Int) {
        func fetch(source: Int, tab: Int) async throws -> (items: [Drama], hasMore: Bool, nextCursor: String) {
            let result = try await readCollection(
                "creatorWorks",
                payload: [
                    "userId": id,
                    "cursor": cursor,
                    "count": String(count),
                    "commentSource": String(source),
                    "tabType": String(tab)
                ],
                loggedIn: loggedIn,
                attempt: attempt,
                account: account
            )
            guard let rows = result["items"] as? [[String: Any]] else {
                throw HongguoAccountError.interactionInvalid
            }
            let dramas: [Drama] = rows.compactMap { row in
                guard let sid = row["id"] as? String, !sid.isEmpty,
                      let title = row["title"] as? String, !title.isEmpty else { return nil }
                return Drama(
                    id: "hongguo:\(sid)",
                    source: "hongguo",
                    sourceId: sid,
                    title: title,
                    description: row["description"] as? String ?? "",
                    cover: row["cover"] as? String ?? "",
                    episodes: (row["episodes"] as? NSNumber)?.intValue ?? 0,
                    tags: row["tags"] as? [String] ?? []
                )
            }
            let hasMore = result["hasMore"] as? Bool ?? false
            let nextCursor = result["nextCursor"] as? String ?? ""
            return (dramas, hasMore, nextCursor)
        }

        let primary = try await fetch(source: commentSource, tab: tabType)
        if !primary.items.isEmpty || !cursor.isEmpty || (commentSource == 1504 && tabType == 1) {
            return (primary.items, primary.hasMore, primary.nextCursor, commentSource, tabType)
        }
        if let fallback = try? await fetch(source: 1504, tab: 1), !fallback.items.isEmpty {
            return (fallback.items, fallback.hasMore, fallback.nextCursor, 1504, 1)
        }
        return (primary.items, primary.hasMore, primary.nextCursor, commentSource, tabType)
    }

    func followingCreators(
        offset: Int = 0,
        loggedIn: Bool,
        attempt: Int,
        account: HongguoAccountRecord?
    ) async throws -> HongguoCollectionPage<Anchor> {
        let revision = vault.snapshot.revision
        if collectionIdentity?.revision != revision {
            var targetId = account?.id ?? ""
            if let profile = try? await creatorProfile(targetId, loggedIn: loggedIn, attempt: attempt, account: account),
               !profile.id.isEmpty {
                targetId = profile.id
            }
            guard vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
            collectionIdentity = (revision, targetId)
        }
        let userId = collectionIdentity?.id ?? account?.id ?? ""
        let result = try await readCollection(
            "followingCreators",
            payload: ["userId": userId, "offset": String(offset), "count": "20"],
            loggedIn: loggedIn,
            attempt: attempt,
            account: account
        )
        guard let rows = result["creators"] as? [[String: Any]], let more = result["hasMore"] as? Bool else {
            throw HongguoAccountError.interactionInvalid
        }
        return HongguoCollectionPage(
            items: rows.compactMap { Anchor(official: $0) },
            hasMore: more,
            nextOffset: result["nextOffset"] as? Int,
            douyinOffset: result["followingDouyinNextOffset"] as? Int ?? 0
        )
    }

    func likedVideos(
        offset: Int = 0,
        loggedIn: Bool,
        attempt: Int,
        account: HongguoAccountRecord?
    ) async throws -> HongguoCollectionPage<HongguoLikedVideo> {
        let result = try await readCollection(
            "likedVideos",
            payload: ["offset": String(offset), "count": "20"],
            loggedIn: loggedIn,
            attempt: attempt,
            account: account
        )
        guard let rows = result["items"] as? [[String: Any]], let more = result["hasMore"] as? Bool else {
            throw HongguoAccountError.interactionInvalid
        }
        return HongguoCollectionPage(
            items: rows.compactMap { HongguoLikedVideo(row: $0) },
            hasMore: more,
            nextOffset: result["nextOffset"] as? Int,
            unsupportedCount: result["unsupportedCount"] as? Int ?? 0
        )
    }

    func readCreators(
        _ drama: Drama,
        owner: Int,
        attempt: Int,
        account: HongguoAccountRecord?
    ) async throws -> [HongguoCreator] {
        let result = try await transportService.call(
            "creatorList",
            payload: ["id": drama.cleanSourceId],
            owner: owner,
            attempt: attempt,
            existing: true,
            account: account,
            cookies: []
        ).result
        guard let rows = result["creators"] as? [[String: Any]] else { throw HongguoAccountError.invalid }
        return rows.compactMap(HongguoCreator.init)
    }

    func readSocial(
        _ drama: Drama,
        owner: Int,
        attempt: Int,
        account: HongguoAccountRecord?
    ) async throws -> HongguoSocialSnapshot {
        let revision = vault.snapshot.revision
        let result = try await transportService.call(
            "socialDetail",
            payload: ["id": drama.cleanSourceId],
            owner: owner,
            attempt: attempt,
            existing: true,
            account: account,
            cookies: []
        ).result
        guard vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        guard result["id"] as? String == drama.cleanSourceId, let rows = result["episodes"] as? [[String: Any]] else {
            throw HongguoAccountError.invalid
        }
        var creators: [HongguoCreator] = []
        var creatorError: String?
        do {
            creators = try await readCreators(drama, owner: owner, attempt: attempt, account: account)
        } catch {
            try transportService.check(owner: owner, attempt: attempt)
            creatorError = error.localizedDescription
        }
        return HongguoSocialSnapshot(
            episodes: rows.compactMap(HongguoEpisodeLike.init),
            creators: creators,
            creatorError: creatorError
        )
    }
}
