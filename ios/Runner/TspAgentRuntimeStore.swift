import Foundation

@objc class TspAgentRuntimeStore: NSObject {
  @objc static func isWanted() -> Bool { return false }
  @objc static func save(configPath: String, statePath: String?) {}
  @objc static func clear() {}
  @objc static func configPath() -> String? { return nil }
  @objc static func statePath() -> String? { return nil }
}
