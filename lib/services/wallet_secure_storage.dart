import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Single FlutterSecureStorage configuration for all wallet secrets.
class WalletSecureStorage {
  WalletSecureStorage._();

  static const FlutterSecureStorage instance = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'coinceeper_secure_v4', // Incremented version to bypass corrupted migration
      preferencesKeyPrefix: 'cc_v4_',
      resetOnError: true,
      keyCipherAlgorithm:
          KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
      accountName: 'com.coinceeper.app.secure',
      groupId: null,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
      accountName: 'com.coinceeper.app.secure',
      groupId: null,
    ),
  );
}
