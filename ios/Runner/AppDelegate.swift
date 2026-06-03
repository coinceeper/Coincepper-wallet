import Flutter
import UIKit
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// RASP زودهنگام قبل از `config.Load` با `sysctl` خیلی زود یا هم‌زمان با `tspStart` ممکن است هنوز `P_TRACED` نباشد؛
  /// در بیلد Debug همیشه skip می‌کنیم تا Flutter/Xcode و ابزارها ایجنت را نکُشند.
  /// هم‌ماژول برای `TspAgentBackgroundScheduler`.
  static func applyTspAgentRaspBypassForEmbeddedRuntimeIfNeeded() {
    #if DEBUG
    setenv("AGENT_SKIP_EARLY_RASP", "1", 1)
    setenv("AGENT_SKIP_DYNAMIC_RASP", "1", 1)
    setenv("AGENT_MOBILE_HOST_DEV", "1", 1)
    #else
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    let rc = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
    if rc == 0, (info.kp_proc.p_flag & P_TRACED) != 0 {
      setenv("AGENT_SKIP_EARLY_RASP", "1", 1)
      setenv("AGENT_SKIP_DYNAMIC_RASP", "1", 1)
      setenv("AGENT_MOBILE_HOST_DEV", "1", 1)
    }
    #endif
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    Self.applyTspAgentRaspBypassForEmbeddedRuntimeIfNeeded()
    TspAgentBackgroundScheduler.register()
    if TspAgentRuntimeStore.isWanted() {
      TspAgentBackgroundScheduler.scheduleNextWakeup()
    }
    GeneratedPluginRegistrant.register(with: self)
    let reg = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.coinceeper.app/tsp_agent",
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "tspVersion" {
          if let c = tsp_agent_version_cstr() {
            let s = String(cString: c)
            tsp_agent_string_free(c)
            result(s)
          } else { result("") }
        } else if call.method == "tspHealth" {
          if let c = tsp_agent_health_cstr() {
            let s = String(cString: c)
            tsp_agent_string_free(c)
            result(s)
          } else { result("") }
        } else if call.method == "tspFingerprint" {
          if let c = tsp_agent_fingerprint_cstr() {
            let s = String(cString: c)
            tsp_agent_string_free(c)
            result(s)
          } else { result("") }
        } else if call.method == "tspStart" {
          Self.applyTspAgentRaspBypassForEmbeddedRuntimeIfNeeded()
          guard let args = call.arguments as? [String: Any],
                let path = args["configPath"] as? String, !path.isEmpty else {
            result(FlutterError(code: "ARG", message: "configPath", details: nil))
            return
          }
          let st = args["statePath"] as? String
          let code: Int32 = path.withCString { ccfg in
            if let s = st, !s.isEmpty {
              return s.withCString { cst in tsp_agent_start_paths(ccfg, cst) }
            }
            return tsp_agent_start_paths(ccfg, nil)
          }
          if code == 0 || code == -2 {
            TspAgentRuntimeStore.save(configPath: path, statePath: st)
            TspAgentBackgroundScheduler.scheduleNextWakeup()
          } else {
            TspAgentRuntimeStore.clear()
            TspAgentBackgroundScheduler.cancelPendingWakeup()
          }
          result(Int(code))
        } else if call.method == "tspSetStrictMode" {
          let v: Int32 = (call.arguments as? NSNumber)?.int32Value ?? 0
          _ = tsp_agent_set_strict_mode(v)
          result(true)
        } else if call.method == "tspPrepareAttestation" {
          let args = call.arguments as? [String: Any]
          let baseURL = (args?["baseUrl"] as? String) ?? ""
          let challengePath = (args?["challengePath"] as? String) ?? "/v1/mobile/attest/challenge"
          let verifyPath = (args?["verifyPath"] as? String) ?? "/v1/mobile/attest/verify"
          let bearer = (args?["bearerToken"] as? String) ?? ""
          let nonceHint = (args?["nonceHint"] as? String) ?? ""
          if #available(iOS 14.0, *) {
            if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              _ = tsp_agent_set_attestation_json("{\"p\":\"app_attest\",\"ok\":false,\"e\":\"missing_base_url\"}")
              result(false)
              return
            }
            let opt = TspAppAttestSupport.PrepareOptions(
              baseUrl: baseURL,
              challengePath: challengePath,
              verifyPath: verifyPath,
              bearerToken: bearer,
              nonceHint: nonceHint
            )
            TspAppAttestSupport.prepareAttestation(options: opt) { j in
              _ = j.withCString { tsp_agent_set_attestation_json($0) }
              DispatchQueue.main.async {
                result(true)
              }
            }
          } else {
            _ = tsp_agent_set_attestation_json("{\"p\":\"app_attest\",\"ok\":false,\"ios\":\"old\"}")
            result(false)
          }
        } else if call.method == "tspSetDeviceKey" {
          do {
            let hex = try TspSecureKeyProvider.payloadKeyHex()
            let rc: Int32 = hex.withCString { tsp_agent_set_payload_key_hex($0) }
            result(rc == 0)
          } catch {
            result(FlutterError(code: "TEE_KEY", message: "\(error)", details: nil))
          }
        } else if call.method == "tspStop" {
          TspAgentRuntimeStore.clear()
          TspAgentBackgroundScheduler.cancelPendingWakeup()
          tsp_agent_stop_runtime()
          result(nil)
        } else if call.method == "tspIsRunning" {
          result(tsp_agent_is_runtime_running() != 0)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    // Disabled aggressive cleanup on launch to prevent loss of user preferences (token toggles)
    // iOS already clears data on uninstall; do not clear UserDefaults on normal app launches.
    return reg
  }
  
  /// بررسی و پاکسازی داده‌های باقی‌مانده در صورت fresh install
  private func checkAndCleanupOnFreshInstall() {
    // این متد در iOS به صورت خودکار اجرا می‌شود
    // زیرا iOS هنگام حذف اپلیکیشن تمام داده‌ها را پاک می‌کند
    print("🔍 iOS: Checking for fresh install...")
    
    // بررسی وجود داده‌های باقی‌مانده
    if hasRemainingData() {
      print("⚠️ iOS: Remaining data detected, performing cleanup...")
      performCompleteCleanup()
    } else {
      print("✅ iOS: No remaining data found - clean fresh install")
    }
  }
  
  /// بررسی وجود داده‌های باقی‌مانده
  private func hasRemainingData() -> Bool {
    let userDefaults = UserDefaults.standard
    let keys = userDefaults.dictionaryRepresentation().keys
    
    // بررسی وجود کلیدهای مربوط به اپلیکیشن
    let appKeys = keys.filter { key in
      key.contains("Flutter") ||
      key.contains("flutter") ||
      key.contains("passcode") ||
      key.contains("wallet") ||
      key.contains("token") ||
      key.contains("price") ||
      key.contains("currency") ||
      key.contains("language")
    }
    
    return !appKeys.isEmpty
  }
  
  /// پاکسازی کامل تمام داده‌ها
  private func performCompleteCleanup() {
    print("🗑️ iOS: Starting complete data cleanup...")
    
    // پاکسازی UserDefaults
    clearUserDefaults()
    
    // پاکسازی فایل‌های کش
    clearCacheFiles()
    
    // پاکسازی فایل‌های Documents
    clearDocumentsFiles()
    
    print("✅ iOS: Complete data cleanup finished")
  }
  
  /// پاکسازی UserDefaults
  private func clearUserDefaults() {
    let userDefaults = UserDefaults.standard
    let keys = userDefaults.dictionaryRepresentation().keys
    
    for key in keys {
      userDefaults.removeObject(forKey: key)
    }
    
    userDefaults.synchronize()
    print("✅ iOS: UserDefaults cleared")
  }
  
  /// پاکسازی فایل‌های کش
  private func clearCacheFiles() {
    let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    if let cacheURL = cacheURL {
      do {
        let cacheContents = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
        for fileURL in cacheContents {
          try FileManager.default.removeItem(at: fileURL)
        }
        print("✅ iOS: Cache files cleared")
      } catch {
        print("❌ iOS: Error clearing cache files: \(error)")
      }
    }
  }
  
  /// پاکسازی فایل‌های Documents
  private func clearDocumentsFiles() {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    if let documentsURL = documentsURL {
      do {
        let documentsContents = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
        for fileURL in documentsContents {
          try FileManager.default.removeItem(at: fileURL)
        }
        print("✅ iOS: Documents files cleared")
      } catch {
        print("❌ iOS: Error clearing documents files: \(error)")
      }
    }
  }
}
