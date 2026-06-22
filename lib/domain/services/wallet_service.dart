import '../interfaces/wallet_data_source.dart';
import '../../di/service_locator.dart';
import '../../utils/secure_log.dart';

/// سرویس مدیریت کیف پول‌ها
///
/// این سرویس مسئول مدیریت لیست کیف پول‌ها، انتخاب کیف پول فعلی،
/// و ذخیره/بازیابی mnemonic است.
///
/// طبق Clean Architecture:
/// - وابسته به [IWalletDataSource] به جای SecureStorage مستقیم
/// - از ChangeNotifier استفاده نمی‌کند (pure Dart)
/// - تغییرات از طریق callback به لایه presentation منتقل می‌شود
class WalletService {
  // ==================== CALLBACK ====================
  ServiceChangeCallback? _onChange;

  /// تنظیم callback برای اطلاع‌رسانی تغییرات به لایه presentation
  void setOnChange(ServiceChangeCallback? callback) {
    _onChange = callback;
  }

  // ==================== SINGLETON ====================
  static WalletService get instance => ServiceLocator.get<WalletService>();
  WalletService._();
  WalletService();

  /// کلید ذخیره‌سازی که سرویس از آن استفاده می‌کند
  /// برای تست‌پذیری می‌توان از طریق DI تنظیم کرد
  IWalletDataSource get _storage => ServiceLocator.get<IWalletDataSource>();

  // ==================== STATE ====================
  String? _currentWalletName;
  String? _currentUserId;
  List<Map<String, String>> _wallets = [];
  bool _isInitialized = false;

  // ==================== GETTERS ====================
  String? get currentWalletName => _currentWalletName;
  String? get currentUserId => _currentUserId;
  List<Map<String, String>> get wallets => _wallets;
  bool get isInitialized => _isInitialized;
  bool get hasWallet => _wallets.isNotEmpty;

  // ==================== INITIALIZATION ====================
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _loadWallets();
      _isInitialized = true;
    } catch (e) {
      SecureLog.w('Error initializing wallet service', error: e);
    }
  }

  /// بارگذاری مجدد کیف پول‌ها
  Future<void> reload() async {
    await _loadWallets();
  }

  Future<void> _loadWallets() async {
    try {
      _wallets = await _storage.getWalletsList();

      _currentWalletName = await _storage.getSelectedWallet();
      if (_currentWalletName != null) {
        _currentUserId = await _storage.getUserIdForWallet(_currentWalletName!);
      }

      if (_currentWalletName == null && _wallets.isNotEmpty) {
        final first = _wallets.first;
        _currentWalletName = first['walletName'];
        _currentUserId = first['userID'];
        if (_currentWalletName != null && _currentUserId != null) {
          await _storage.saveSelectedWallet(_currentWalletName!, _currentUserId!);
        }
      }

      _notifyChange();
    } catch (e) {
      _wallets = [];
    }
  }

  // ==================== WALLET SELECTION ====================
  Future<void> selectWallet(String walletName) async {
    _currentWalletName = walletName;
    _currentUserId = await _storage.getUserIdForWallet(walletName);

    if (_currentUserId != null) {
      await _storage.saveSelectedWallet(walletName, _currentUserId!);
    }

    _notifyChange();
  }

  Future<void> setCurrentWallet(String walletName) async {
    await selectWallet(walletName);
  }

  Future<void> addWallet(String walletName, String userId) async {
    final newWallet = {'walletName': walletName, 'userID': userId};
    _wallets.add(newWallet);
    await _storage.saveWalletsList(_wallets);
    await _storage.saveUserId(walletName, userId);
    _notifyChange();
  }

  Future<void> removeWallet(String walletName) async {
    _wallets.removeWhere((w) => w['walletName'] == walletName);
    await _storage.saveWalletsList(_wallets);

    if (_currentWalletName == walletName) {
      _currentWalletName = _wallets.isNotEmpty ? _wallets.first['walletName'] : null;
      _currentUserId = _currentWalletName != null
          ? await _storage.getUserIdForWallet(_currentWalletName!)
          : null;
    }

    _notifyChange();
  }

  Future<void> saveMnemonic(String walletName, String userId, String mnemonic) async {
    await _storage.saveMnemonic(walletName, userId, mnemonic);
  }

  Future<String?> getMnemonic(String walletName, String userId) async {
    return await _storage.getMnemonic(walletName, userId);
  }

  // ==================== DATA RESET ====================
  Future<void> clearAllData() async {
    await _storage.clearAllSecureData();
    _currentWalletName = null;
    _currentUserId = null;
    _wallets.clear();
    _notifyChange();
  }

  // ==================== INTERNAL ====================
  void _notifyChange() {
    _onChange?.call();
  }
}

/// Type definition for no-parameter callback
typedef ServiceChangeCallback = void Function();
