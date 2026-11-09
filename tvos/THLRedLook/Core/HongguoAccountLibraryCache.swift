import Foundation

final class HongguoAccountLibraryCache: @unchecked Sendable {
    static let shared = HongguoAccountLibraryCache()
    private let lock = NSLock()
    private var revision: UInt64 = .max
    private var watches: [String: WatchEntry] = [:]
    private var historyIds: Set<String> = []
    private var favorites: [String: Drama] = [:]
    private var favoriteOrder: [String] = []

    static func id(_ value: String) -> String {
        value.hasPrefix("hongguo:") ? String(value.dropFirst(8)) : value
    }

    func handles(_ id: String) -> Bool {
        let record = HongguoAccountVault.shared.snapshot.record
        return record?.hasSession == true &&
            (id.hasPrefix("hongguo:") || id.range(of: "^\\d{10,30}$", options: .regularExpression) != nil)
    }

    private func resetIfNeeded() {
        let current = HongguoAccountVault.shared.snapshot.revision
        if revision != current {
            revision = current
            watches = [:]
            favorites = [:]
            historyIds = []
            favoriteOrder = []
        }
    }

    func watch(_ id: String) -> WatchEntry? {
        lock.withLock {
            resetIfNeeded()
            return watches[Self.id(id)]
        }
    }

    func followed(_ id: String) -> Bool {
        lock.withLock {
            resetIfNeeded()
            return favorites[Self.id(id)] != nil
        }
    }

    func entries(history: Bool) -> [WatchEntry] {
        lock.withLock {
            resetIfNeeded()
            if history {
                return historyIds.compactMap { watches[$0] }.sorted { $0.updatedAt > $1.updatedAt }
            }
            return favoriteOrder.compactMap { favorites[$0] }.map {
                WatchEntry(drama: $0, episode: 0, position: 0, duration: 0, updatedAt: Date(timeIntervalSince1970: 0))
            }
        }
    }

    func update(_ rows: [WatchEntry], history: Bool, owner: UInt64, preserving: Set<String> = []) {
        lock.withLock {
            resetIfNeeded()
            guard revision == owner else { return }
            if history {
                historyIds = Set(rows.map { Self.id($0.drama.id) }).union(preserving)
                for row in rows {
                    let key = Self.id(row.drama.id)
                    if watches[key] == nil || watches[key]!.updatedAt <= row.updatedAt {
                        watches[key] = row
                    }
                }
            } else {
                favoriteOrder = rows.map { Self.id($0.drama.id) }
                favorites = Dictionary(rows.map { (Self.id($0.drama.id), $0.drama) }, uniquingKeysWith: { _, last in last })
            }
        }
    }

    func progress(_ entry: WatchEntry?, id: String, owner: UInt64, recordHistory: Bool = false) {
        lock.withLock {
            resetIfNeeded()
            guard revision == owner else { return }
            watches[Self.id(id)] = entry
            if entry == nil {
                historyIds.remove(Self.id(id))
            } else if recordHistory {
                historyIds.insert(Self.id(id))
            }
        }
    }

    func follow(_ drama: Drama, add: Bool, owner: UInt64) {
        lock.withLock {
            resetIfNeeded()
            guard revision == owner else { return }
            favorites[Self.id(drama.id)] = add ? drama : nil
            favoriteOrder.removeAll { $0 == Self.id(drama.id) }
            if add {
                favoriteOrder.insert(Self.id(drama.id), at: 0)
            }
        }
    }
}
