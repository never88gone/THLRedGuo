import Foundation

public struct CatalogCategory: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static let all = CatalogCategory(id: "", name: "全部")
}
