import Foundation
import Security

/// DeepSeek API Key 本地存储；兼容从旧版 macOS Keychain 一次性迁移。
struct KeychainStore: Sendable {
    private let service = "com.quietpaper.deepseek"
    private let account = "deepseek_api_key"
    private let localDefaultsKey = "deepseek_api_key_local"

    /// 本地测试工具优先保存在应用设置中，避免每次调用 AI 都触发钥匙串授权。
    func set(value: String) throws {
        guard value.data(using: .utf8) != nil else { throw KeychainError.invalidData }
        UserDefaults.standard.set(value, forKey: localDefaultsKey)
    }

    /// 首次升级时从旧钥匙串迁移一次；之后只读本地缓存，不再重复弹出授权。
    func get() -> String? {
        if let cached = UserDefaults.standard.string(forKey: localDefaultsKey), !cached.isEmpty {
            return cached
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        guard let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        UserDefaults.standard.set(value, forKey: localDefaultsKey)
        return value
    }

    /// 清除本地缓存。旧钥匙串项目保留，便于旧版本继续使用。
    func delete() throws {
        UserDefaults.standard.removeObject(forKey: localDefaultsKey)
    }
}

enum KeychainError: LocalizedError {
    case invalidData
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "无法将 API Key 编码为 UTF-8"
        case .unexpectedStatus(let status):
            "Keychain 操作失败（状态码：\(status)）"
        }
    }
}
