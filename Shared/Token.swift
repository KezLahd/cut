import Foundation
import Security

/// The GitHub token for cloud fetch. It lives in the Keychain under the App Group, so the share extension can
/// start a fetch the moment a link is shared. The repo name isn't secret and sits in shared defaults.
enum CloudConfig {
    private static let service = "com.kezlahd.cut.cloud"
    static let defaultRepo = "KezLahd/cut-fetcher"
    static let workflow = "video.yml"

    static var repo: String {
        get { AppGroup.defaults.string(forKey: "cloudRepo") ?? defaultRepo }
        set { AppGroup.defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "cloudRepo") }
    }

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccessGroup as String: AppGroup.id, kSecUseDataProtectionKeychain as String: true]
    }

    static var token: String? {
        get {
            var q = base
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            SecItemDelete(base as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var add = base
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
