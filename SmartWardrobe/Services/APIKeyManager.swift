import Foundation
import Security
import os.log

final class APIKeyManager {
    private let logger = Logger(subsystem: "SmartWardrobe", category: "APIKeyManager")
    static let shared = APIKeyManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let llmAPIKey = "llm_api_key"
        static let qWeatherAPIKey = "qweather_api_key"
        static let qWeatherAPIHost = "qweather_api_host"
        static let keychainMigrated = "keychain_migrated_v1"
    }

    init() {
        migrateToKeychainIfNeeded()
    }

    // MARK: - API Key Properties

    var llmAPIKey: String? {
        get { keychainRead(Keys.llmAPIKey) }
        set { keychainWrite(Keys.llmAPIKey, value: newValue) }
    }

    var qWeatherAPIKey: String? {
        get { keychainRead(Keys.qWeatherAPIKey) }
        set { keychainWrite(Keys.qWeatherAPIKey, value: newValue) }
    }

    var qWeatherAPIHost: String? {
        get { defaults.string(forKey: Keys.qWeatherAPIHost) }
        set { defaults.set(newValue, forKey: Keys.qWeatherAPIHost) }
    }

    // MARK: - URL Builders

    /// 清理并校验 host：只允许字母数字点横线
    private func sanitizedHost(_ raw: String?) -> String? {
        guard let host = raw?.trimmingCharacters(in: .whitespaces), !host.isEmpty else { return nil }
        let cleaned = host
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard cleaned.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              cleaned.contains(".") else { return nil }
        return cleaned
    }

    /// 获取天气 API 的完整基础 URL
    var qWeatherBaseURL: String {
        if let trimmed = sanitizedHost(qWeatherAPIHost) {
            return "https://\(trimmed)/v7/weather/now"
        }
        return AppConstants.API.qWeatherBaseURL
    }

    /// 获取地理位置 API 的完整基础 URL
    var qWeatherGeoURL: String {
        if let trimmed = sanitizedHost(qWeatherAPIHost) {
            return "https://\(trimmed)/geo/v2/city/lookup"
        }
        return AppConstants.API.qWeatherGeoURL
    }

    /// 3 日天气预报 URL
    var qWeatherForecastURL: String {
        if let trimmed = sanitizedHost(qWeatherAPIHost) {
            return "https://\(trimmed)/v7/weather/3d"
        }
        return AppConstants.API.qWeatherForecastURL
    }

    var llmBaseURL: String? {
        get { defaults.string(forKey: "llm_base_url") }
        set { defaults.set(newValue, forKey: "llm_base_url") }
    }

    var llmModel: String? {
        get { defaults.string(forKey: "llm_model") }
        set { defaults.set(newValue, forKey: "llm_model") }
    }

    // MARK: - Status

    var isLLMConfigured: Bool {
        guard let key = llmAPIKey, !key.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = llmBaseURL, !url.trimmingCharacters(in: .whitespaces).isEmpty,
              let model = llmModel, !model.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        return true
    }

    var isWeatherConfigured: Bool {
        guard let key = qWeatherAPIKey, !key.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return true
    }

    var isFullyConfigured: Bool {
        isLLMConfigured && isWeatherConfigured
    }

    // MARK: - Keychain Helpers

    private func keychainRead(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.smartwardrobe",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.warning("Keychain read error for \(key): \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private func keychainWrite(_ key: String, value: String?) -> Bool {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.smartwardrobe"
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return true }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.smartwardrobe",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Migration

    /// 从 UserDefaults 迁移到 Keychain（一次性，部分失败则下次重试）
    private func migrateToKeychainIfNeeded() {
        guard !defaults.bool(forKey: Keys.keychainMigrated) else { return }

        var allSuccess = true
        if let key = defaults.string(forKey: Keys.llmAPIKey), !key.isEmpty {
            if keychainWrite(Keys.llmAPIKey, value: key) {
                defaults.removeObject(forKey: Keys.llmAPIKey)
            } else {
                allSuccess = false
            }
        }
        if let key = defaults.string(forKey: Keys.qWeatherAPIKey), !key.isEmpty {
            if keychainWrite(Keys.qWeatherAPIKey, value: key) {
                defaults.removeObject(forKey: Keys.qWeatherAPIKey)
            } else {
                allSuccess = false
            }
        }

        if allSuccess {
            defaults.set(true, forKey: Keys.keychainMigrated)
        }
    }
}
