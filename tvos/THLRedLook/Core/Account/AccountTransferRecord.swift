import Foundation

enum AccountTransferRecord {
    static func decode(_ data: Data) throws -> HongguoAccountRecord {
        guard data.count <= 48 * 1024, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["v"] as? Int == 1, Set(root.keys) == Set(["v", "id", "cookies", "device"]),
            let id = root["id"] as? String, id.range(of: "^[0-9]{1,30}$", options: .regularExpression) != nil,
            let raw = root["cookies"] as? [[String: Any]], !raw.isEmpty, raw.count <= 16,
            let device = root["device"] as? [String: String], Set(device.keys) == Set(["iid", "device_id", "cdid"]),
            let cdid = device["cdid"], !cdid.isEmpty, cdid.count <= 80 else { throw HongguoAccountError.invalid }
        for field in ["iid", "device_id"] {
            guard device[field]?.range(of: "^[0-9]{10,24}$", options: .regularExpression) != nil else { throw HongguoAccountError.invalid }
        }
        var names = Set<String>()
        let cookies = try raw.map { row -> HongguoCookie in
            guard Set(row.keys).isSubset(of: Set(["name", "value", "domain", "path", "expires"])),
                let name = row["name"] as? String, HongguoAccountVault.credentialNames.contains(name), names.insert(name).inserted,
                let value = row["value"] as? String, !value.isEmpty, value.count <= 4096,
                value.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value <= 0x7e && ![34, 44, 59, 92].contains($0.value) }),
                row["domain"] as? String == "hongguoduanju.com", row["path"] as? String == "/" else { throw HongguoAccountError.invalid }
            var expires: Date?
            if let stamp = row["expires"], !(stamp is NSNull) {
                guard let number = stamp as? NSNumber else { throw HongguoAccountError.invalid }
                expires = Date(timeIntervalSince1970: number.doubleValue / 1000)
            }
            return HongguoCookie(name: name, value: value, domain: "hongguoduanju.com", path: "/", expires: expires)
        }
        guard cookies.contains(where: { $0.valid && ["sessionid", "sessionid_ss"].contains($0.name) }) else { throw HongguoAccountError.invalid }
        return HongguoAccountRecord(id: id, nickname: "", cookies: cookies, device: device)
    }
}
