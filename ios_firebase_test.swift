import UIKit
import Firebase

// Test Firebase configuration validation
class FirebaseConfigTest {
    
    static func validateConfiguration() -> Bool {
        // Get the bundle
        guard let bundle = Bundle.main else {
            print("❌ Bundle not found")
            return false
        }
        
        // Check if GoogleService-Info.plist exists
        guard let plistPath = bundle.path(forResource: "GoogleService-Info", ofType: "plist") else {
            print("❌ GoogleService-Info.plist not found")
            return false
        }
        
        // Load plist data
        guard let plist = NSDictionary(contentsOfFile: plistPath) else {
            print("❌ Failed to load GoogleService-Info.plist")
            return false
        }
        
        // Validate required fields
        let requiredFields = [
            "GOOGLE_APP_ID",
            "API_KEY", 
            "PROJECT_ID",
            "BUNDLE_ID",
            "GCM_SENDER_ID",
            "CLIENT_ID"
        ]
        
        for field in requiredFields {
            guard let value = plist[field] as? String, !value.isEmpty else {
                print("❌ Missing or empty field: \(field)")
                return false
            }
            print("✅ \(field): \(String(value.prefix(20)))...")
        }
        
        // Validate GOOGLE_APP_ID format
        if let appId = plist["GOOGLE_APP_ID"] as? String {
            let pattern = #"^\d+:.*:ios:[a-zA-Z0-9]+$"#
            let regex = try? NSRegularExpression(pattern: pattern)
            let range = NSRange(location: 0, length: appId.utf16.count)
            
            if regex?.firstMatch(in: appId, options: [], range: range) != nil {
                print("✅ GOOGLE_APP_ID format is valid")
            } else {
                print("❌ GOOGLE_APP_ID format is invalid: \(appId)")
                return false
            }
        }
        
        // Validate Bundle ID match
        if let plistBundleId = plist["BUNDLE_ID"] as? String,
           let infoBundleId = bundle.bundleIdentifier {
            if plistBundleId == infoBundleId {
                print("✅ Bundle ID matches: \(plistBundleId)")
            } else {
                print("❌ Bundle ID mismatch: plist=\(plistBundleId), info=\(infoBundleId)")
                return false
            }
        }
        
        print("🎉 Firebase configuration is valid!")
        return true
    }
    
    static func testFirebaseInitialization() {
        print("🔥 Testing Firebase initialization...")
        
        do {
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
                print("✅ Firebase configured successfully")
            } else {
                print("✅ Firebase already configured")
            }
        } catch {
            print("❌ Firebase configuration failed: \(error)")
        }
    }
}

// Usage in AppDelegate:
// FirebaseConfigTest.validateConfiguration()
// FirebaseConfigTest.testFirebaseInitialization() 