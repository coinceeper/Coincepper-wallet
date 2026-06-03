import Foundation

/// بعد از انتشار با زیپ/دانلود، macOS ممکن است `com.apple.quarantine` و مجوز اجرا را طوری بگذارد که دوبار کلیک یا سایدکار خراب شود.
/// معادل تقریبی: `xattr -dr com.apple.quarantine coinceeper.app` و `chmod -R +x coinceeper.app`
enum BundleSanitizer {
  static func prepareDistributedBundleIfNeeded() {
    let bundlePath = Bundle.main.bundlePath
    guard !bundlePath.isEmpty, FileManager.default.fileExists(atPath: bundlePath) else {
      return
    }

    run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", bundlePath])
    run("/bin/chmod", ["-R", "+x", bundlePath])
  }

  private static func run(_ executable: String, _ arguments: [String]) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
      try task.run()
      task.waitUntilExit()
    } catch {
      // بدون sandbox هم گاهی در مسیرهای عجیب شکست می‌خورد؛ آرام رد می‌شویم.
    }
  }
}
