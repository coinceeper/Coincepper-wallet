import Foundation
import Security
import CryptoKit

enum TspSecureKeyProvider {
  private static let enclTag = "com.coinceeper.app.tsp.enclave.ec.v1".data(using: .utf8)!
  private static let fallbackService = "com.coinceeper.app.tsp"
  private static let fallbackAccount = "agent_payload_key_v1"

  static func payloadKeyHex() throws -> String {
    if let h = try? enclaveDerivedKeyHex() { return h }
    return try fallbackKeychainHex()
  }

  private static func enclaveDerivedKeyHex() throws -> String {
    let priv = try getOrCreateEnclavePrivateKey()
    let msg = Data(("tsp-agent-payload-key:" + (Bundle.main.bundleIdentifier ?? "app")).utf8)
    var err: Unmanaged<CFError>?
    guard let sig = SecKeyCreateSignature(priv, .ecdsaSignatureMessageX962SHA256, msg as CFData, &err) as Data? else {
      throw (err?.takeRetainedValue() as Error?) ?? NSError(domain: "tsp", code: -1)
    }
    let digest = SHA256.hash(data: sig)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
  }

  private static func getOrCreateEnclavePrivateKey() throws -> SecKey {
    if let existing = copyEnclavePrivateKey() { return existing }
    let access = SecAccessControlCreateWithFlags(
      kCFAllocatorDefault,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      .privateKeyUsage,
      nil
    )!
    let attrs: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: enclTag,
        kSecAttrAccessControl as String: access,
      ],
    ]
    var err: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &err) else {
      throw (err?.takeRetainedValue() as Error?) ?? NSError(domain: "tsp", code: -2)
    }
    return key
  }

  private static func copyEnclavePrivateKey() -> SecKey? {
    let q: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: enclTag,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecReturnRef as String: true,
    ]
    var out: CFTypeRef?
    let st = SecItemCopyMatching(q as CFDictionary, &out)
    if st == errSecSuccess { return (out as! SecKey) }
    return nil
  }

  private static func fallbackKeychainHex() throws -> String {
    if let existing = readFallback() { return existing }
    var raw = Data(count: 32)
    _ = raw.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
    let hex = raw.map { String(format: "%02x", $0) }.joined()
    try writeFallback(hex)
    return hex
  }

  private static func readFallback() -> String? {
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: fallbackService,
      kSecAttrAccount as String: fallbackAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: CFTypeRef?
    let st = SecItemCopyMatching(q as CFDictionary, &out)
    guard st == errSecSuccess, let d = out as? Data, let s = String(data: d, encoding: .utf8) else {
      return nil
    }
    return s
  }

  private static func writeFallback(_ hex: String) throws {
    let d = Data(hex.utf8)
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: fallbackService,
      kSecAttrAccount as String: fallbackAccount,
      kSecValueData as String: d,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
    ]
    SecItemDelete(q as CFDictionary)
    let st = SecItemAdd(q as CFDictionary, nil)
    if st != errSecSuccess { throw NSError(domain: "tsp", code: Int(st)) }
  }
}
