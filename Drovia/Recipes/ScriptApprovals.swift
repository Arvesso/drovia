import CryptoKit
import Foundation
import os
import Security

/// Recipe scripts run with Drovia's permissions (allowed folders, Full Disk Access, control of Finder), but
/// they're stored in the preferences file, which any process of the user can rewrite. So a script runs only
/// if the user typed it in Drovia's recipe editor or approved it when asked.
///
/// Approvals are HMACs of the script text under a key in the user's keychain. Another app can't read that key
/// without macOS asking the user, so it can't mark a script of its own as approved, and an entry that merely
/// exists proves nothing (unlike storing hashes as keychain items, which any app may add).
@MainActor
final class ScriptApprovals {
    /// Holds the HMAC key.
    protocol KeyStore {
        func key() throws -> SymmetricKey
    }

    private static let defaultsKey = "approvedScripts"

    private let defaults: UserDefaults
    private let keyStore: any KeyStore
    private var cachedKey: SymmetricKey?

    init(defaults: UserDefaults, keyStore: any KeyStore) {
        self.defaults = defaults
        self.keyStore = keyStore
    }

    func isApproved(_ script: String) -> Bool {
        authenticationCode(for: script).map(stored.contains) ?? false
    }

    func approve(_ script: String) {
        guard let code = authenticationCode(for: script) else { return }
        var approved = stored
        if approved.insert(code).inserted {
            save(approved)
        }
    }

    /// Forgets approvals of scripts no recipe has any more, so typing in the editor doesn't pile them up.
    func keepOnly(_ scripts: [String]) {
        let current = Set(scripts.compactMap(authenticationCode))
        let approved = stored
        if !approved.isSubset(of: current) {
            save(approved.intersection(current))
        }
    }

    private var stored: Set<String> {
        Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    private func save(_ approved: Set<String>) {
        defaults.set(approved.sorted(), forKey: Self.defaultsKey)
    }

    private func authenticationCode(for script: String) -> String? {
        do {
            let key = try cachedKey ?? keyStore.key()
            cachedKey = key
            return Data(HMAC<SHA256>.authenticationCode(for: Data(script.utf8), using: key))
                .map { String(format: "%02x", $0) }.joined()
        } catch {
            // Without the key nothing counts as approved; the user is asked before each run instead.
            Logger.wheel.error("Script approval key unavailable: \(error.localizedDescription)")
            return nil
        }
    }
}

/// The HMAC key as a generic password in the login keychain, made on first use. Its access list trusts only
/// Drovia, so other apps reading it make macOS ask the user. (With ad-hoc signing every build is a different
/// app to the keychain, which then asks once per build; `make signing` avoids that.)
struct KeychainScriptKey: ScriptApprovals.KeyStore {
    private static let service = "com.arvesso.drovia.script-approval"
    private static let account = "hmac-key"

    struct Failure: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }

    func key() throws -> SymmetricKey {
        var item: CFTypeRef?
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecReturnData: true,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw Failure(status: status) }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecAttrLabel: "Drovia script approvals",
            kSecValueData: data,
        ]
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure(status: added) }
        return key
    }
}
