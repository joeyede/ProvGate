import Foundation
import Security

struct Credentials {
    var username: String?
    var password: String?
    var rememberMe: Bool
}

final class CredentialsStore {
    private let service: String
    private let usernameAccount = "username"
    private let passwordAccount = "password"
    private var rememberMeKey: String { "\(service).remember_me" }

    init(service: String = "ProvGate.MQTT") {
        self.service = service
    }

    // Only call with rememberMe: true. For the rememberMe=false case call clear() directly.
    func save(username: String, password: String, rememberMe: Bool) {
        precondition(rememberMe, "save() called with rememberMe=false; call clear() instead")
        UserDefaults.standard.set(true, forKey: rememberMeKey)
        setKeychain(account: usernameAccount, value: username)
        setKeychain(account: passwordAccount, value: password)
    }

    func load() -> Credentials {
        let rememberMe = UserDefaults.standard.bool(forKey: rememberMeKey)
        return Credentials(
            username: getKeychain(account: usernameAccount),
            password: getKeychain(account: passwordAccount),
            rememberMe: rememberMe
        )
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: rememberMeKey)
        deleteKeychain(account: usernameAccount)
        deleteKeychain(account: passwordAccount)
    }

    private func setKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Include accessibility in the update so existing items are migrated too.
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            precondition(addStatus == errSecSuccess, "Keychain add failed: \(addStatus)")
        } else {
            precondition(status == errSecSuccess, "Keychain update failed: \(status)")
        }
    }

    private func getKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
