import Foundation
import Combine

// MARK: - 红果官方账号会话与书架状态管理器

@MainActor
final class HongguoAccountModel: ObservableObject {
    static let shared = HongguoAccountModel()

    @Published private(set) var account = HongguoAccountVault.shared.snapshot.record
    @Published private(set) var verified = false
    @Published private(set) var qrURL: String?
    @Published private(set) var remaining = 0
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    @Published private(set) var libraryVersion = 0
    @Published private(set) var libraryWriteError: String?
    @Published private(set) var socialStates: [String: HongguoSocialSnapshot] = [:]
    @Published private(set) var socialBusy: Set<String> = []

    private var socialOwner: UInt64 = .max
    private var socialGeneration: [String: UInt64] = [:]
    private var accountWrites: Task<Void, Error>?
    private var socialWrites: Task<Void, Error>?
    private var reportedAt: [String: Date] = [:]
    private var favoriteGeneration: UInt64 = 0
    private var progressGeneration: [String: UInt64] = [:]
    private var favoriteRevision: UInt64?
    private var attempt = 0

    private let vault = HongguoAccountVault.shared
    private let transportService = HongguoAccountTransport()
    private lazy var loginService = HongguoAccountLoginService(transportService: transportService, vault: vault)

    var loggedIn: Bool {
        account?.hasSession == true
    }

    func cancel() {
        attempt += 1
        loginService.cancel {
            busy = false
            message = ""
            qrURL = nil
        }
    }

    func begin() {
        cancel()
        let currentAttempt = attempt
        loginService.begin(
            attempt: currentAttempt,
            onUpdate: { [weak self] url, remainingSeconds, isBusy, msg in
                guard let self, self.attempt == currentAttempt else { return }
                self.qrURL = url
                self.remaining = remainingSeconds
                self.busy = isBusy
                self.message = msg
            },
            onSuccess: { [weak self] record in
                guard let self, self.attempt == currentAttempt else { return }
                self.account = record
                self.verified = true
                self.qrURL = nil
                self.busy = false
                self.message = "红果账号已登录"
            },
            onError: { [weak self] errorMsg in
                guard let self, self.attempt == currentAttempt else { return }
                self.qrURL = nil
                self.busy = false
                self.message = errorMsg
            }
        )
    }

    func sendPhoneCode(country: String, number: String) async throws {
        let currentAttempt = attempt
        busy = true
        defer { if currentAttempt == attempt { busy = false } }
        let msg = try await loginService.sendPhoneCode(country: country, number: number, attempt: currentAttempt, busy: false) { [weak self] in
            self?.cancel()
        }
        message = msg
    }

    func loginPhone(country: String, number: String, code: String) async throws {
        let currentAttempt = attempt
        busy = true
        defer { if currentAttempt == attempt { busy = false } }
        let record = try await loginService.loginPhone(country: country, number: number, code: code, attempt: currentAttempt, busy: false) { [weak self] in
            self?.cancel()
        }
        account = record
        verified = true
        message = "红果账号已登录"
    }

    func prepareTransferred(_ candidate: HongguoAccountRecord, expectedRevision: UInt64, isCurrent: () -> Bool) async throws -> HongguoVerifiedTransfer {
        try await loginService.prepareTransferred(candidate, expectedRevision: expectedRevision, attempt: attempt, isCurrent: isCurrent)
    }

    func commitTransferred(_ transfer: HongguoVerifiedTransfer, isCurrent: () -> Bool) throws {
        try loginService.commitTransferred(transfer, attempt: attempt, isCurrent: isCurrent)
        account = transfer.record
        verified = true
        message = "红果账号已登录"
    }

    func verify(force: Bool = false) async {
        guard loggedIn, !busy, force || !verified else { return }
        let owner = attempt
        busy = true
        defer { busy = false }
        do {
            let (profile, _, _) = try await transportService.call("profile", owner: owner, attempt: attempt, existing: true, account: account, cookies: [])
            try transportService.check(owner: owner, attempt: attempt)
            guard profile["id"] as? String == account?.id else { throw HongguoAccountError.invalid }
            if let current = account {
                account = HongguoAccountRecord(
                    id: current.id,
                    nickname: profile["nickname"] as? String ?? current.nickname,
                    cookies: current.cookies,
                    device: current.device,
                    avatar: profile["avatar"] as? String ?? current.avatar
                )
            }
            verified = true
        } catch {
            transportService.trace(phase: "verify", error: error, existing: true, account: account, cookies: [])
        }
    }

    func library(history: Bool) async throws -> [WatchEntry] {
        guard loggedIn else { throw HongguoAccountError.invalid }
        let owner = attempt
        let revision = vault.snapshot.revision
        let generation = favoriteGeneration, progressSnapshot = progressGeneration
        let response = try await transportService.call(history ? "history" : "favorites", payload: history ? [:] : ["userId": account?.id ?? ""], owner: owner, attempt: attempt, existing: true, account: account, cookies: []).result
        guard let rows = response["items"] as? [[String: Any]] else { throw HongguoAccountError.invalid }
        var details: [String: [String: Any]] = [:]
        for offset in stride(from: 0, to: rows.count, by: 50) {
            let ids = rows.dropFirst(offset).prefix(50).compactMap { $0["id"] as? String }.joined(separator: ",")
            let response = try await transportService.call("libraryDetails", payload: ["ids": ids], owner: owner, attempt: attempt, existing: true, account: account, cookies: []).result
            guard let entries = response["items"] as? [[String: Any]] else { throw HongguoAccountError.invalid }
            for entry in entries { if let id = entry["id"] as? String { details[id] = entry } }
        }
        try transportService.check(owner: owner, attempt: attempt)
        guard vault.snapshot.revision == revision, loggedIn else { throw HongguoAccountError.cancelled }
        let entries: [WatchEntry] = rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let detail = details[id] ?? row
            let title = detail["title"] as? String ?? ""
            let count = (detail["episodes"] as? NSNumber)?.intValue ?? 0
            let drama = Drama(id: "hongguo:" + id, sourceId: id, title: title.isEmpty ? "剧集" + id : title,
                description: detail["description"] as? String ?? "", cover: detail["cover"] as? String ?? "",
                episodes: count > 0 ? count : (row["episodes"] as? NSNumber)?.intValue ?? 0)
            return WatchEntry(drama: drama, episode: (row["episode"] as? NSNumber)?.intValue ?? 0,
                position: ((row["positionMs"] as? NSNumber)?.doubleValue ?? 0) / 1000,
                duration: ((row["durationMs"] as? NSNumber)?.doubleValue ?? 0) / 1000,
                updatedAt: Date(timeIntervalSince1970: ((row["updatedAt"] as? NSNumber)?.doubleValue ?? 0) / 1000))
        }
        if history || generation == favoriteGeneration {
            HongguoAccountLibraryCache.shared.update(entries, history: history, owner: revision, preserving: Set(progressGeneration.filter { $0.value > (progressSnapshot[$0.key] ?? 0) }.keys.map(HongguoAccountLibraryCache.id)))
            if !history { favoriteRevision = revision }
            publishLibraryChange()
        }
        return HongguoAccountLibraryCache.shared.entries(history: history)
    }

    func publishLibraryChange() {
        libraryVersion += 1
    }

    func prepareLibrary(_ drama: Drama) async throws {
        guard loggedIn else { return }
        if favoriteRevision != vault.snapshot.revision {
            _ = try await library(history: false)
        }
    }

    func progress(_ drama: Drama) async throws -> WatchEntry? {
        guard loggedIn else { return nil }
        let revision = vault.snapshot.revision
        let owner = attempt
        let generation = (progressGeneration[drama.id] ?? 0) + 1
        progressGeneration[drama.id] = generation
        let rows = try await Self.progressRows(id: drama.cleanSourceId) { action, payload in
            try await self.transportService.call(action, payload: payload, owner: owner, attempt: self.attempt, existing: true, account: self.account, cookies: []).result
        }
        guard vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        let row = rows.first { $0["id"] as? String == drama.cleanSourceId }
        let entry = row.map { row in
            WatchEntry(
                drama: drama,
                episode: (row["episode"] as? NSNumber)?.intValue ?? 0,
                position: ((row["positionMs"] as? NSNumber)?.doubleValue ?? 0) / 1000,
                duration: ((row["durationMs"] as? NSNumber)?.doubleValue ?? 0) / 1000,
                updatedAt: Date(timeIntervalSince1970: ((row["updatedAt"] as? NSNumber)?.doubleValue ?? 0) / 1000)
            )
        }
        if generation == progressGeneration[drama.id] ?? 0 {
            HongguoAccountLibraryCache.shared.progress(entry, id: drama.id, owner: revision)
            publishLibraryChange()
        }
        return HongguoAccountLibraryCache.shared.watch(drama.id)
    }

    static func progressRows(id: String, request: (String, [String: String]) async throws -> [String: Any]) async throws -> [[String: Any]] {
        do {
            let response = try await request("progressGet", ["id": id])
            guard let rows = response["items"] as? [[String: Any]] else { throw HongguoAccountError.invalid }
            return rows
        } catch HongguoAccountError.business(101112) {
            let response = try await request("history", [:])
            guard let rows = response["items"] as? [[String: Any]], rows.contains(where: { $0["id"] as? String == id }) else {
                throw HongguoAccountError.business(101112)
            }
            return rows
        }
    }

    private func enqueueWrite(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let revision = vault.snapshot.revision
        let previous = accountWrites
        let task = Task { @MainActor in
            _ = await previous?.result
            guard self.loggedIn, self.vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
            try await operation()
            guard self.vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        }
        accountWrites = task
        do {
            try await task.value
            libraryWriteError = nil
        } catch {
            if vault.snapshot.revision == revision {
                libraryWriteError = "账号同步失败，请检查网络后重试"
            }
            throw error
        }
    }

    func setFollowing(_ drama: Drama, add: Bool?) async throws {
        let revision = vault.snapshot.revision
        try await enqueueWrite {
            let follow = add ?? !HongguoAccountLibraryCache.shared.followed(drama.id)
            let owner = self.attempt
            _ = try await self.transportService.call("favoriteUpdate", payload: ["id": drama.cleanSourceId, "follow": follow ? "1" : "0"], owner: owner, attempt: self.attempt, existing: true, account: self.account, cookies: [])
            let check = try await self.transportService.call("favorites", payload: ["userId": self.account?.id ?? ""], owner: owner, attempt: self.attempt, existing: true, account: self.account, cookies: []).result
            guard let rows = check["items"] as? [[String: Any]],
                  rows.contains(where: { $0["id"] as? String == drama.cleanSourceId }) == follow,
                  self.vault.snapshot.revision == revision else { throw HongguoAccountError.invalid }
            self.favoriteGeneration += 1
            HongguoAccountLibraryCache.shared.follow(drama, add: follow, owner: revision)
            self.publishLibraryChange()
        }
    }

    func uploadProgress(_ entry: WatchEntry, itemId: String, force: Bool) async throws {
        let revision = vault.snapshot.revision
        let key = "\(revision):\(entry.drama.id):\(entry.episode)"
        if !force, Date().timeIntervalSince(reportedAt[key] ?? .distantPast) < 30 { return }
        reportedAt[key] = Date()
        try await enqueueWrite {
            _ = try await self.transportService.call(
                "progressUpdate",
                payload: [
                    "id": entry.drama.cleanSourceId,
                    "itemId": itemId,
                    "episode": String(entry.episode),
                    "positionMs": String(Int(entry.position * 1000)),
                    "durationMs": String(Int(entry.duration * 1000)),
                    "episodes": String(entry.drama.episodes),
                    "updatedAt": String(Int(entry.updatedAt.timeIntervalSince1970 * 1000))
                ],
                owner: self.attempt,
                attempt: self.attempt,
                existing: true,
                account: self.account,
                cookies: []
            )
            guard self.vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
            self.progressGeneration[entry.drama.id] = (self.progressGeneration[entry.drama.id] ?? 0) + 1
            HongguoAccountLibraryCache.shared.progress(entry, id: entry.drama.id, owner: revision, recordHistory: true)
            self.publishLibraryChange()
        }
    }

    private func enqueueSocialWrite(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let revision = vault.snapshot.revision
        let previous = socialWrites
        let task = Task { @MainActor in
            _ = await previous?.result
            guard self.loggedIn, self.vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
            try await operation()
            guard self.vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        }
        socialWrites = task
        try await task.value
    }

    func socialState(_ drama: Drama) -> HongguoSocialSnapshot? {
        guard loggedIn, socialOwner == vault.snapshot.revision else { return nil }
        return socialStates[drama.cleanSourceId]
    }

    private func prepareSocialOwner() {
        if socialOwner != vault.snapshot.revision {
            socialOwner = vault.snapshot.revision
            socialStates = [:]
            socialGeneration = [:]
            socialBusy = []
        }
    }

    private func readCreators(_ drama: Drama, owner: Int) async throws -> [HongguoCreator] {
        let result = try await transportService.call("creatorList", payload: ["id": drama.cleanSourceId], owner: owner, attempt: attempt, existing: true, account: account, cookies: []).result
        guard let rows = result["creators"] as? [[String: Any]] else { throw HongguoAccountError.invalid }
        return rows.compactMap(HongguoCreator.init)
    }

    private func readSocial(_ drama: Drama, owner: Int) async throws -> HongguoSocialSnapshot {
        let revision = vault.snapshot.revision
        let result = try await transportService.call("socialDetail", payload: ["id": drama.cleanSourceId], owner: owner, attempt: attempt, existing: true, account: account, cookies: []).result
        guard vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        guard result["id"] as? String == drama.cleanSourceId, let rows = result["episodes"] as? [[String: Any]] else {
            throw HongguoAccountError.invalid
        }
        var creators: [HongguoCreator] = []
        var creatorError: String?
        do {
            creators = try await readCreators(drama, owner: owner)
        } catch {
            try transportService.check(owner: owner, attempt: attempt)
            creatorError = error.localizedDescription
        }
        return HongguoSocialSnapshot(episodes: rows.compactMap(HongguoEpisodeLike.init), creators: creators, creatorError: creatorError)
    }

    func loadSocial(_ drama: Drama) async throws {
        guard loggedIn else { throw HongguoAccountError.invalid }
        prepareSocialOwner()
        let revision = vault.snapshot.revision
        let id = drama.cleanSourceId
        let generation = socialGeneration[drama.cleanSourceId] ?? 0
        let result = try await readSocial(drama, owner: attempt)
        guard vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
        if socialGeneration[id] ?? 0 == generation {
            socialStates[id] = result
        }
    }

    func setLiked(_ drama: Drama, episode: HongguoEpisodeLike, liked: Bool) async throws {
        guard loggedIn else { throw HongguoAccountError.invalid }
        prepareSocialOwner()
        let revision = vault.snapshot.revision
        let id = drama.cleanSourceId
        guard !socialBusy.contains(id) else { return }
        socialBusy.insert(id)
        defer { if vault.snapshot.revision == revision { socialBusy.remove(id) } }
        try await enqueueSocialWrite {
            _ = try await self.transportService.call("likeUpdate", payload: ["itemId": episode.id, "like": liked ? "1" : "0"], owner: self.attempt, attempt: self.attempt, existing: true, account: self.account, cookies: [])
            guard self.vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
            let result = try await self.readSocial(drama, owner: self.attempt)
            guard self.vault.snapshot.revision == revision, let row = result.episode(episode.number), row.id == episode.id, row.liked == liked else {
                throw HongguoAccountError.writeNotConfirmed
            }
            self.socialGeneration[id] = (self.socialGeneration[id] ?? 0) + 1
            self.socialStates[id] = result
        }
    }

    func setCreatorFollowing(_ drama: Drama, creator: HongguoCreator, follow: Bool) async throws {
        guard loggedIn, creator.following != nil, creator.canFollow || !follow, creator.id != account?.id else {
            throw HongguoAccountError.invalid
        }
        prepareSocialOwner()
        let revision = vault.snapshot.revision
        let id = drama.cleanSourceId
        guard !socialBusy.contains(id) else { return }
        socialBusy.insert(id)
        defer { if vault.snapshot.revision == revision { socialBusy.remove(id) } }
        try await enqueueSocialWrite {
            _ = try await self.transportService.call("creatorFollow", payload: ["userId": creator.id, "relativeType": String(creator.relativeType), "follow": follow ? "1" : "0"], owner: self.attempt, attempt: self.attempt, existing: true, account: self.account, cookies: [])
            guard self.vault.snapshot.revision == revision else { throw HongguoAccountError.cancelled }
            let rows = try await self.readCreators(drama, owner: self.attempt)
            guard self.vault.snapshot.revision == revision, let row = rows.first(where: { $0.id == creator.id && $0.relativeType == creator.relativeType }), row.following == follow else {
                throw HongguoAccountError.writeNotConfirmed
            }
            self.socialGeneration[id] = (self.socialGeneration[id] ?? 0) + 1
            self.socialStates[id] = HongguoSocialSnapshot(
                episodes: self.socialStates[id]?.episodes ?? [],
                creators: rows,
                creatorError: self.socialStates[id]?.creatorError
            )
        }
    }

    func logout() {
        cancel()
        _ = try? vault.logout()
        account = nil
        verified = false
        message = ""
        socialStates = [:]
        socialBusy = []
        favoriteRevision = nil
        HongguoAccountLibraryCache.shared.update([], history: true, owner: vault.snapshot.revision)
        HongguoAccountLibraryCache.shared.update([], history: false, owner: vault.snapshot.revision)
        publishLibraryChange()
    }
}
