import 'package:shared_preferences/shared_preferences.dart';
import '../models/address_book_entry.dart';

/// سرویس مدیریت دفترچه آدرس با منطق مشابه نسخه Kotlin
class AddressBookService {
  /// ذخیره یک کیف پول جدید (مطابق با saveWalletToKeystore در Kotlin)
  static Future<void> saveWalletToKeystore(String walletName, String walletAddress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wallet_name_$walletName', walletName);
    await prefs.setString('wallet_address_$walletName', walletAddress);
  }

  /// بارگذاری همه کیف پول‌ها (مطابق با loadWalletsFromKeystore در Kotlin)
  static Future<List<AddressBookEntry>> loadWalletsFromKeystore() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    final walletNames = allKeys.where((k) => k.startsWith('wallet_name_')).toList();
    List<AddressBookEntry> wallets = [];
    for (final nameKey in walletNames) {
      final walletName = prefs.getString(nameKey) ?? '';
      final walletAddress = prefs.getString('wallet_address_$walletName') ?? '';
      if (walletName.isNotEmpty && walletAddress.isNotEmpty) {
        wallets.add(AddressBookEntry(name: walletName, address: walletAddress));
      }
    }
    return wallets;
  }

  /// حذف کیف پول (مطابق با حذف در Kotlin)
  static Future<void> deleteWalletFromKeystore(String walletName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wallet_name_$walletName');
    await prefs.remove('wallet_address_$walletName');
  }

  // متدهای قبلی غیرفعال شدند و فقط برای سازگاری باقی مانده‌اند
  @deprecated
  static Future<List<AddressBookEntry>> loadWallets() async => loadWalletsFromKeystore();
  @deprecated
  static Future<void> addWallet(AddressBookEntry wallet) async => saveWalletToKeystore(wallet.name, wallet.address);
  @deprecated
  static Future<void> updateWallet(int index, AddressBookEntry wallet) async => saveWalletToKeystore(wallet.name, wallet.address);
  @deprecated
  static Future<void> deleteWallet(int index) async {/* حذف بر اساس index دیگر پشتیبانی نمی‌شود */}
} 