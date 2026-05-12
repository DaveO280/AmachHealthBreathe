// WalletService.swift
// AmachBreatheShared — lifted from AmachHealth-iOS
//
// Privy wallet integration. Handles authentication, embedded wallet management,
// and PBKDF2 encryption key derivation (cross-platform compatible with web app).
//
// PBKDF2 parameters MUST match Amach-Website/src/utils/walletEncryption.ts exactly:
//   algorithm: SHA-256 · iterations: 100,000 · key length: 32 bytes
//   salt: wallet address hex bytes (first 20 bytes after stripping 0x)
//
// iOS only — watchOS uses WatchConnectivity to request keys from the paired iPhone.

import Foundation

#if os(iOS)
import Combine

#if canImport(PrivySDK)
import PrivySDK
#endif

// MARK: - WalletService

@MainActor
public final class WalletService: ObservableObject {

    public static let shared = WalletService()

    @Published public var isConnected = false
    @Published public var address: String?
    @Published public var encryptionKey: WalletEncryptionKey?
    @Published public var isLoading = false
    @Published public var error: String?
    @Published public var pendingEmail: String?
    @Published public var hasAuthenticatedBefore: Bool

    // Reuse existing Amach Health Privy app (spec: "reuse existing Amach Health Privy app")
    private let privyAppId    = "cmiev4g03026zl80cpoyjccwu"
    private let privyClientId = "client-WY6TLxngkdjGfUtmZkKe5evREPGvJ7Z7jeQXBd5BcxJE5"

    #if canImport(PrivySDK)
    private var privy: (any Privy)?
    #endif

    // MARK: Key Derivation Constants (MUST match walletEncryption.ts — never change)
    static let encryptionKeyMessagePrefix =
        "Amach Health - Derive Encryption Key\n\nThis signature is used to encrypt your health data.\n\nNonce: "

    private init() {
        self.hasAuthenticatedBefore = UserDefaults.standard.bool(forKey: "amach_breathe_has_authenticated")
    }

    // MARK: - Privy Setup

    public func initializePrivy() {
        #if canImport(PrivySDK)
        let config = PrivyConfig(appId: privyAppId, appClientId: privyClientId)
        self.privy = PrivySdk.initialize(config: config)
        Task { await restoreSessionIfAvailable() }
        #else
        print("⚠️ PrivySDK not installed — running in dev-mock mode.")
        Task { try? await connectDevMock() }
        #endif
    }

    // MARK: - Email OTP Login

    public func sendEmailCode(to email: String) async throws {
        error = nil
        let normalizedEmail: String
        do {
            normalizedEmail = try Self.normalizedEmailForCode(email)
        } catch {
            self.error = error.localizedDescription
            throw error
        }
        #if canImport(PrivySDK)
        guard let privy else {
            let walletError = WalletError.notConfigured
            self.error = walletError.localizedDescription
            throw walletError
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await privy.email.sendCode(to: normalizedEmail)
            pendingEmail = normalizedEmail
        } catch {
            self.error = Self.visibleMessage(
                for: error,
                fallback: "We couldn't send a code. Make sure the email matches your Amach Health account, then try again."
            )
            throw error
        }
        #else
        pendingEmail = normalizedEmail
        #endif
    }

    public func loginWithEmailCode(_ code: String) async throws {
        error = nil
        #if canImport(PrivySDK)
        guard let privy else {
            let walletError = WalletError.notConfigured
            self.error = walletError.localizedDescription
            throw walletError
        }
        guard let email = pendingEmail else {
            let walletError = WalletError.noPendingEmailCode
            self.error = walletError.localizedDescription
            throw walletError
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let user = try await privy.email.loginWithCode(code, sentTo: email)
            try await finishConnecting(user: user)
            pendingEmail = nil
        } catch {
            self.error = Self.visibleMessage(
                for: error,
                fallback: "We couldn't verify that code. Check the code and try again, or request a new one."
            )
            throw WalletError.connectionFailed(error)
        }
        #else
        try await connectDevMock()
        pendingEmail = nil
        #endif
    }

    public func clearPendingEmailCode() {
        pendingEmail = nil
        error = nil
    }

    public static func normalizedEmailForCode(_ email: String) throws -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"),
              normalized.contains("."),
              normalized.count > 4 else {
            throw WalletError.invalidEmail
        }
        return normalized
    }

    private static func visibleMessage(for error: Error, fallback: String) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty || message == "The operation couldn’t be completed." {
            return fallback
        }
        return message
    }

    #if canImport(PrivySDK)
    private func finishConnecting(user: any PrivyUser) async throws {
        let wallet: any EmbeddedEthereumWallet
        if let existing = user.embeddedEthereumWallets.first {
            wallet = existing
        } else {
            wallet = try await user.createEthereumWallet()
        }
        self.address = wallet.address.lowercased()
        self.isConnected = true
        self.hasAuthenticatedBefore = true
        UserDefaults.standard.set(true, forKey: "amach_breathe_has_authenticated")

        if let cached = try? loadEncryptionKeyFromKeychain(for: wallet.address.lowercased()) {
            self.encryptionKey = cached
            return
        }
        try await deriveAndStoreEncryptionKey(wallet: wallet)
    }

    private func restoreSessionIfAvailable() async {
        guard let privy else { return }
        let authState = await privy.getAuthState()
        guard case .authenticated(let user) = authState,
              let wallet = user.embeddedEthereumWallets.first else { return }
        self.address = wallet.address.lowercased()
        self.isConnected = true
        if let cached = try? loadEncryptionKeyFromKeychain(for: wallet.address.lowercased()) {
            self.encryptionKey = cached
        }
    }
    #endif

    // MARK: - Dev Mock

    public func connectDevMock() async throws {
        isLoading = true
        defer { isLoading = false }
        let devAddress = "0xdev0000000000000000000000000000amachdev1"
        let mockSig = "0x" + String(repeating: "ab", count: 65)
        let derived = try Self.deriveEncryptionKeyPBKDF2(signatureHex: mockSig, walletAddress: devAddress)
        let key = WalletEncryptionKey(
            walletAddress: devAddress,
            encryptionKey: derived,
            signature: mockSig,
            timestamp: Int(Date().timeIntervalSince1970 * 1000)
        )
        self.encryptionKey = key
        try? saveEncryptionKeyToKeychain()
        self.address = devAddress
        self.isConnected = true
    }

    // MARK: - Disconnect

    public func disconnect() async {
        if let addr = address { deleteEncryptionKeyFromKeychain(for: addr) }
        isConnected = false
        address = nil
        encryptionKey = nil
        #if canImport(PrivySDK)
        if let privy, case .authenticated(let user) = await privy.getAuthState() {
            await user.logout()
        }
        #endif
    }

    // MARK: - Ensure Key

    public func ensureEncryptionKey(forceRefresh: Bool = false) async throws -> WalletEncryptionKey {
        guard isConnected else { throw WalletError.notConnected }
        if !forceRefresh, let key = encryptionKey { return key }
        try await rederiveEncryptionKey()
        guard let key = encryptionKey else { throw WalletError.noEncryptionKey }
        return key
    }

    private func rederiveEncryptionKey() async throws {
        guard isConnected else { throw WalletError.notConnected }
        #if canImport(PrivySDK)
        guard let privy,
              case .authenticated(let user) = await privy.getAuthState(),
              let wallet = user.embeddedEthereumWallets.first else {
            throw WalletError.notConnected
        }
        try await deriveAndStoreEncryptionKey(wallet: wallet)
        #else
        throw WalletError.notImplemented
        #endif
    }

    // MARK: - PBKDF2 Derivation

    #if canImport(PrivySDK)
    private func deriveAndStoreEncryptionKey(wallet: any EmbeddedEthereumWallet) async throws {
        isLoading = true
        defer { isLoading = false }
        let address = wallet.address.lowercased()
        let message = Self.encryptionKeyMessagePrefix + address
        let req = EthereumRpcRequest(method: "personal_sign", params: [message, wallet.address])
        let sig = try await wallet.provider.request(req)
        guard sig.count >= 132 else { throw WalletError.signingFailed(NSError(domain: "WalletService", code: -2)) }
        let derived = try Self.deriveEncryptionKeyPBKDF2(signatureHex: sig, walletAddress: address)
        let key = WalletEncryptionKey(
            walletAddress: address,
            encryptionKey: derived,
            signature: sig,
            timestamp: Int(Date().timeIntervalSince1970 * 1000)
        )
        self.encryptionKey = key
        try saveEncryptionKeyToKeychain()
    }
    #endif

    /// PBKDF2-SHA256 key derivation. Delegates to WalletCrypto (platform-shared).
    public static func deriveEncryptionKeyPBKDF2(
        signatureHex: String,
        walletAddress: String
    ) throws -> String {
        try WalletCrypto.deriveEncryptionKey(signatureHex: signatureHex, walletAddress: walletAddress)
    }

    public static func hexToBytes(_ hex: String) throws -> [UInt8] {
        try WalletCrypto.hexToBytes(hex)
    }

    // MARK: - Keychain

    public func saveEncryptionKeyToKeychain() throws {
        guard let key = encryptionKey else { throw WalletError.noEncryptionKey }
        let data = try JSONEncoder().encode(key)
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      "breathe_enc_\(key.walletAddress)",
            kSecAttrService as String:      "com.amach.breathe",
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw WalletError.keychainError(status) }
    }

    public func loadEncryptionKeyFromKeychain(for address: String) throws -> WalletEncryptionKey {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: "breathe_enc_\(address)",
            kSecAttrService as String: "com.amach.breathe",
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw WalletError.keychainError(status) }
        return try JSONDecoder().decode(WalletEncryptionKey.self, from: data)
    }

    public func deleteEncryptionKeyFromKeychain(for address: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: "breathe_enc_\(address)",
            kSecAttrService as String: "com.amach.breathe"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

public enum WalletError: LocalizedError, Sendable {
    case notConnected
    case notConfigured
    case notImplemented
    case invalidEmail
    case noPendingEmailCode
    case noEncryptionKey
    case invalidHex
    case connectionFailed(Error)
    case signingFailed(Error)
    case keyDerivationFailed(Int32)
    case keychainError(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .notConnected:           return "Wallet is not connected"
        case .notConfigured:          return "Privy SDK not configured"
        case .notImplemented:         return "Privy SDK not installed"
        case .invalidEmail:           return "Enter a valid email address to receive a code."
        case .noPendingEmailCode:     return "Request a new email code before verifying."
        case .noEncryptionKey:        return "No encryption key available"
        case .invalidHex:             return "Invalid hex string"
        case .connectionFailed(let e): return "Connection failed: \(e.localizedDescription)"
        case .signingFailed(let e):   return "Signing failed: \(e.localizedDescription)"
        case .keyDerivationFailed(let s): return "PBKDF2 failed (status: \(s))"
        case .keychainError(let s):   return "Keychain error: \(s)"
        }
    }
}

#endif // os(iOS)
