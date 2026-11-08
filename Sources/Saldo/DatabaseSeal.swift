import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// On-disk envelope for the SQLite snapshot. The bytes are unreadable without Saldo's key file.
enum DatabaseSeal {
    static let magic = Data("SALDO1".utf8)

    static func isSealed(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else {
            throw StoreError.message("Could not encrypt the database.")
        }
        return magic + combined
    }

    static func open(_ data: Data, using key: SymmetricKey) throws -> Data {
        guard data.count > magic.count, isSealed(data) else {
            throw StoreError.message("This file is not an encrypted Saldo database.")
        }
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
            return try AES.GCM.open(box, using: key)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.message(
                "Could not decrypt this database. Saldo left the saved file in place."
            )
        }
    }
}

/// Random database key kept in Saldo's private folder, not the Keychain.
///
/// The login Keychain ties access to the app's code signature. Saldo is re-signed on
/// every install, so macOS asked for the keychain password each time the key was read.
/// Touch ID still gates when this file is read, and the key is dropped from memory on lock.
enum DatabaseKeystore {
    private static let service = "local.saldo.app"
    private static let account = "database-key"
    private static let fileName = "database.key"

    static func loadOrCreate(createIfMissing: Bool, directory: URL) throws -> SymmetricKey {
        let fileURL = directory.appendingPathComponent(fileName)
        if let existing = readKeyFile(at: fileURL) {
            return existing
        }
        // Test data never borrows the real key from the Keychain.
        if !TestDataMode.isActive,
            let existing = try load(dataProtection: false) ?? load(dataProtection: true)
        {
            try? writeKeyFile(existing, to: fileURL)
            return existing
        }
        guard createIfMissing else {
            throw StoreError.message(
                "The database key is missing. Saldo left the saved database in place."
            )
        }
        let key = SymmetricKey(size: .bits256)
        try writeKeyFile(key, to: fileURL)
        return key
    }

    private static func readKeyFile(at url: URL) -> SymmetricKey? {
        guard let data = try? Data(contentsOf: url), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    private static func writeKeyFile(_ key: SymmetricKey, to url: URL) throws {
        let data = key.withUnsafeBytes { Data($0) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func load(dataProtection: Bool) throws -> SymmetricKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if dataProtection {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else {
                throw StoreError.message("The database key in the Keychain is unreadable.")
            }
            return SymmetricKey(data: data)
        case errSecItemNotFound, errSecInteractionNotAllowed, errSecAuthFailed:
            return nil
        default:
            if dataProtection { return nil }
            throw StoreError.message(keychainMessage(status))
        }
    }

    private static func keychainMessage(_ status: OSStatus) -> String {
        if let text = SecCopyErrorMessageString(status, nil) {
            return "Could not open the database key. \(text as String)"
        }
        return "Could not open the database key (error \(status))."
    }
}
