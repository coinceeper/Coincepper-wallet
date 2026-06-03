// Generated from android/app/google-services.json (Android).
// iOS: add GoogleService-Info.plist and extend with ios options from FlutterFire CLI.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions are not configured for web — use FlutterFire configure.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'Add ios FirebaseOptions (GoogleService-Info.plist) via FlutterFire configure.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBnmgQ6SVmxoAXUq4x5HvfA0bppDD_HO3Y',
    appId: '1:189047135032:android:3ff99ffc954ffb40a07fcd',
    messagingSenderId: '189047135032',
    projectId: 'coinceeper-f2eaf',
    storageBucket: 'coinceeper-f2eaf.firebasestorage.app',
  );
}
