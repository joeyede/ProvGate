import Foundation
import Security

struct Credentials {
    var username: String?
    var password: String?
    var rememberMe: Bool
}

final class CredentialsStore {
    private let service: String
    private let keychainAccessGroup: String?
    private let defaults: UserDefaults
    private let usernameAccount = "username"
    private let passwordAccount = "password"
    private var rememberMeKey: String { "\(service).remember_me" }

    init(service: String = "ProvGate.MQTT", keychainAccessGroup: String? = nil, userDefaultsSuite: String? = nil) {
        self.service = service
        self.keychainAccessGroup = keychainAccessGroup
        self.defaults = userDefaultsSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    // Only call with rememberMe: true. For the rememberMe=false case call clear() directly.
    func save(username: String, password: String, rememberMe: Bool) {
        precondition(rememberMe, "save() called with rememberMe=false; call clear() instead")
        defaults.set(true, forKey: rememberMeKey)
        setKeychain(account: usernameAccount, value: username)
        setKeychain(account: passwordAccount, value: password)
    }

    func load() -> Credentials {
        let rememberMe = defaults.bool(forKey: rememberMeKey)
        return Credentials(
            username: getKeychain(account: usernameAccount),
            password: getKeychain(account: passwordAccount),
            rememberMe: rememberMe
        )
    }

    func clear() {
        defaults.removeObject(forKey: rememberMeKey)
        deleteKeychain(account: usernameAccount)
        deleteKeychain(account: passwordAccount)
    }

    private func baseQuery(account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let group = keychainAccessGroup {
            q[kSecAttrAccessGroup as String] = group
        }
        return q
    }

    private func setKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query = baseQuery(account: account)
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
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
