import Foundation

public struct SourceGroup: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let sources: [SourceSite]

    public init(id: String, name: String, sources: [SourceSite]) {
        self.id = id
        self.name = name
        self.sources = sources
    }

    public static func fromSources(_ sources: [SourceSite]) -> [SourceGroup] {
        var map = [String: [SourceSite]]()
        for source in sources {
            map[source.groupId, default: []].append(source)
        }
        var groups = [SourceGroup]()
        for (groupId, list) in map {
            let groupName = list.first?.groupName ?? groupId
            groups.append(SourceGroup(id: groupId, name: groupName, sources: list))
        }
        return groups.sorted { $0.name < $1.name }
    }
}
