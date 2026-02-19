import Foundation
import Security

enum SecureTokenStoreError: LocalizedError {
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Keychain returned data in an unexpected format."
        case let .unhandledStatus(status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

final class SecureTokenStore {
    private let service = "ClickUpTimerGuard"
    private let account = "clickupAPIToken"

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        var query = baseQuery()

        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecureTokenStoreError.unhandledStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw SecureTokenStoreError.unhandledStatus(updateStatus)
        }
    }

    func loadToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecureTokenStoreError.unhandledStatus(status)
        }

        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw SecureTokenStoreError.unexpectedData
        }
        return token
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureTokenStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
