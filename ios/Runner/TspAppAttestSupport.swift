import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// End-to-end App Attest flow (client side):
/// 1) fetch nonce/challenge from backend
/// 2) generate key (once) + attestKey (first-time) or generateAssertion (next times)
/// 3) POST payload to backend verify
/// 4) receive backend attestation token and forward to Go runtime
@available(iOS 14.0, *)
enum TspAppAttestSupport {
  private static let keychainKeyID = "tsp.appattest.key_id"
  private static let sessionTimeout: TimeInterval = 15

  struct PrepareOptions {
    let baseUrl: String
    let challengePath: String
    let verifyPath: String
    let bearerToken: String
    let nonceHint: String

    init(baseUrl: String, challengePath: String, verifyPath: String, bearerToken: String, nonceHint: String) {
      self.baseUrl = baseUrl
      self.challengePath = challengePath
      self.verifyPath = verifyPath
      self.bearerToken = bearerToken
      self.nonceHint = nonceHint
    }
  }

  struct ChallengeResponse: Codable {
    let challengeB64: String
    let challengeId: String

    enum CodingKeys: String, CodingKey {
      case challengeB64 = "challenge_b64"
      case challengeId = "challenge_id"
    }
  }

  struct VerifyResponse: Codable {
    let token: String
  }

  static var isServiceSupported: Bool {
    #if canImport(DeviceCheck) && !targetEnvironment(simulator)
    return DCAppAttestService.shared.isSupported
    #else
    return false
    #endif
  }

  static func prepareAttestation(options: PrepareOptions, completion: @escaping (String) -> Void) {
    #if canImport(DeviceCheck) && canImport(CryptoKit) && !targetEnvironment(simulator)
    guard isServiceSupported else {
      completion(jsonFailure("unsupported_devicecheck"))
      return
    }
    guard let challengeURL = makeURL(base: options.baseUrl, path: options.challengePath),
          let verifyURL = makeURL(base: options.baseUrl, path: options.verifyPath) else {
      completion(jsonFailure("invalid_backend_url"))
      return
    }
    let cfg = URLSessionConfiguration.ephemeral
    cfg.timeoutIntervalForRequest = sessionTimeout
    cfg.timeoutIntervalForResource = sessionTimeout
    let session = URLSession(configuration: cfg)

    fetchChallenge(session: session, url: challengeURL, bearer: options.bearerToken, hint: options.nonceHint) { challengeResult in
      switch challengeResult {
      case .failure(let err):
        completion(jsonFailure("challenge_fetch_failed:\(err.localizedDescription)"))
      case .success(let ch):
        let challengeRaw = Data(base64Encoded: ch.challengeB64) ?? Data(ch.challengeB64.utf8)
        let digest = SHA256.hash(data: challengeRaw)
        let clientDataHash = Data(digest)
        let svc = DCAppAttestService.shared

        withAppAttestKeyID(service: svc) { keyResult in
          switch keyResult {
          case .failure(let err):
            completion(jsonFailure("key_failed:\(err.localizedDescription)"))
          case .success(let keyTuple):
            let keyID = keyTuple.keyID
            let isFreshKey = keyTuple.isFresh
            if isFreshKey {
              svc.attestKey(keyID, clientDataHash: clientDataHash) { attObj, err in
                if let err = err {
                  completion(jsonFailure("attest_failed:\(err.localizedDescription)"))
                  return
                }
                guard let attObj = attObj else {
                  completion(jsonFailure("attest_empty"))
                  return
                }
                submitVerify(
                  session: session,
                  url: verifyURL,
                  bearer: options.bearerToken,
                  challengeID: ch.challengeId,
                  keyID: keyID,
                  challengeB64: ch.challengeB64,
                  artifactB64: attObj.base64EncodedString(),
                  kind: "attestation",
                  completion: completion
                )
              }
            } else {
              svc.generateAssertion(keyID, clientDataHash: clientDataHash) { assertion, err in
                if let err = err {
                  completion(jsonFailure("assert_failed:\(err.localizedDescription)"))
                  return
                }
                guard let assertion = assertion else {
                  completion(jsonFailure("assert_empty"))
                  return
                }
                submitVerify(
                  session: session,
                  url: verifyURL,
                  bearer: options.bearerToken,
                  challengeID: ch.challengeId,
                  keyID: keyID,
                  challengeB64: ch.challengeB64,
                  artifactB64: assertion.base64EncodedString(),
                  kind: "assertion",
                  completion: completion
                )
              }
            }
          }
        }
      }
    }
    #else
    completion(jsonFailure("unsupported_build"))
    #endif
  }

  private static func fetchChallenge(
    session: URLSession,
    url: URL,
    bearer: String,
    hint: String,
    completion: @escaping (Result<ChallengeResponse, Error>) -> Void
  ) {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
    if !bearer.isEmpty {
      req.addValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    }
    let body: [String: String] = [
      "platform": "ios",
      "provider": "app_attest",
      "hint": hint
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let task = session.dataTask(with: req) { data, _, err in
      if let err = err {
        completion(.failure(err))
        return
      }
      guard let data = data else {
        completion(.failure(NSError(domain: "tsp.attest", code: -1)))
        return
      }
      do {
        completion(.success(try JSONDecoder().decode(ChallengeResponse.self, from: data)))
      } catch {
        completion(.failure(error))
      }
    }
    task.resume()
  }

  private static func submitVerify(
    session: URLSession,
    url: URL,
    bearer: String,
    challengeID: String,
    keyID: String,
    challengeB64: String,
    artifactB64: String,
    kind: String,
    completion: @escaping (String) -> Void
  ) {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
    if !bearer.isEmpty {
      req.addValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    }
    let payload: [String: String] = [
      "platform": "ios",
      "provider": "app_attest",
      "kind": kind,
      "challenge_id": challengeID,
      "challenge_b64": challengeB64,
      "key_id": keyID,
      "artifact_b64": artifactB64
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
    let task = session.dataTask(with: req) { data, _, err in
      if let err = err {
        completion(jsonFailure("verify_post_failed:\(err.localizedDescription)"))
        return
      }
      guard let data = data else {
        completion(jsonFailure("verify_empty"))
        return
      }
      if let resp = try? JSONDecoder().decode(VerifyResponse.self, from: data), !resp.token.isEmpty {
        completion("{\"p\":\"app_attest\",\"t\":\"\(escapeJSON(resp.token))\"}")
      } else {
        completion(jsonFailure("verify_bad_response"))
      }
    }
    task.resume()
  }

  private static func withAppAttestKeyID(
    service: DCAppAttestService,
    completion: @escaping (Result<(keyID: String, isFresh: Bool), Error>) -> Void
  ) {
    if let keyID = UserDefaults.standard.string(forKey: keychainKeyID), !keyID.isEmpty {
      completion(.success((keyID: keyID, isFresh: false)))
      return
    }
    service.generateKey { keyID, err in
      if let err = err {
        completion(.failure(err))
        return
      }
      guard let keyID = keyID, !keyID.isEmpty else {
        completion(.failure(NSError(domain: "tsp.attest", code: -2)))
        return
      }
      UserDefaults.standard.set(keyID, forKey: keychainKeyID)
      completion(.success((keyID: keyID, isFresh: true)))
    }
  }

  private static func makeURL(base: String, path: String) -> URL? {
    let b = base.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if b.isEmpty {
      return nil
    }
    let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if p.isEmpty {
      return URL(string: b)
    }
    let p2 = p.hasPrefix("/") ? String(p.dropFirst()) : p
    return URL(string: b + "/" + p2)
  }

  private static func escapeJSON(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }

  private static func jsonFailure(_ message: String) -> String {
    "{\"p\":\"app_attest\",\"ok\":false,\"e\":\"\(escapeJSON(message))\"}"
  }
}
