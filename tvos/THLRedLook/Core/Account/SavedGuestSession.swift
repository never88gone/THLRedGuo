import Foundation

enum SavedGuestSession {
    static func valid(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return ["iid", "device_id"].allSatisfy { key in
            guard let id = value[key] as? String else { return false }
            return id.range(of: "^[1-9][0-9]{9,23}$", options: .regularExpression) != nil
        }
    }
}
