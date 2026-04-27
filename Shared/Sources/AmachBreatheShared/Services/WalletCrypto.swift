// WalletCrypto.swift — platform-independent PBKDF2 key derivation utilities.
// WalletService (iOS-only) delegates to these functions.
// Available on iOS, watchOS, macOS (and therefore testable from swift test).

import Foundation
import CommonCrypto

// MARK: - Key derivation constants (MUST match walletEncryption.ts — never change)

public enum WalletCrypto {

    private static let pbkdf2Iterations      = 100_000
    private static let derivedKeyLengthBytes = 32

    /// PBKDF2-SHA256 derivation. Output matches walletEncryption.ts deriveKeyWithWebCrypto().
    /// - Parameter signatureHex: raw personal_sign result (with or without "0x")
    /// - Parameter walletAddress: lowercase wallet address (with or without "0x")
    public static func deriveEncryptionKey(
        signatureHex: String,
        walletAddress: String
    ) throws -> String {
        let sigHex = signatureHex.hasPrefix("0x") ? String(signatureHex.dropFirst(2)) : signatureHex
        let sigBytes = try hexToBytes(sigHex)

        var saltHex = walletAddress.lowercased()
        if saltHex.hasPrefix("0x") { saltHex = String(saltHex.dropFirst(2)) }
        saltHex = String(saltHex.prefix(40))
        let saltBytes = try hexToBytes(saltHex)

        let derived = try pbkdf2SHA256(
            password: sigBytes,
            salt: saltBytes,
            iterations: pbkdf2Iterations,
            keyLength: derivedKeyLengthBytes
        )
        return derived.map { String(format: "%02x", $0) }.joined()
    }

    public static func hexToBytes(_ hex: String) throws -> [UInt8] {
        guard hex.count % 2 == 0 else { throw WalletCryptoError.invalidHex }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { throw WalletCryptoError.invalidHex }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    private static func pbkdf2SHA256(
        password: [UInt8], salt: [UInt8], iterations: Int, keyLength: Int
    ) throws -> [UInt8] {
        var key = [UInt8](repeating: 0, count: keyLength)
        let status = password.withUnsafeBufferPointer { pw in
            salt.withUnsafeBufferPointer { sl in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pw.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self) },
                    password.count,
                    sl.baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &key, keyLength
                )
            }
        }
        guard status == kCCSuccess else { throw WalletCryptoError.keyDerivationFailed(status) }
        return key
    }
}

public enum WalletCryptoError: LocalizedError, Sendable {
    case invalidHex
    case keyDerivationFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidHex:                   return "Invalid hex string"
        case .keyDerivationFailed(let s):   return "PBKDF2 failed (status: \(s))"
        }
    }
}
