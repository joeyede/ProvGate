import Foundation
import Security

struct Credentials {
    var username: String?
    var password: String?
    var rememberMe: Bool
}

final class CredentialsStore {
    private let service = "ProvGate.MQTT"
    private let usernameAccount = "username"
    private let passwordAccount = "password"
    private let rememberMeKey = "provgate.remember_me"

    func save(username: String, password: String, rememberMe: Bool) {
        UserDefaults.standard.set(rememberMe, forKey: rememberMeKey)
        if rememberMe {
            setKeychain(account: usernameAccount, value: username)
            setKeychain(account: passwordAccount, value: password)
        } else {
            deleteKeychain(account: usernameAccount)
            deleteKeychain(account: passwordAccount)
        }
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
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
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
