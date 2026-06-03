/// Central route path constants.
abstract final class RoutePaths {
  static const splash = '/splash';
  static const importCreate = '/import-create';
  static const importWallet = '/import-wallet';
  static const createNewWallet = '/create-new-wallet';
  static const passcodeSetup = '/passcode-setup';
  static const passcodeConfirm = '/passcode-confirm';
  static const enterPasscode = '/enter-passcode';
  static const phraseKeyConfirm = '/phrase-key-confirm';
  static const insideNewWallet = '/inside-new-wallet';
  static const insideImportWallet = '/inside-import-wallet';
  static const addressBook = '/address-book';
  static const mining = '/mining';
  static const webView = '/webview';
  static const backup = '/backup';
  static const phraseKey = '/phrase-key';
  static const home = '/home';
  static const panel = '/panel';
  static const wallets = '/wallets';
  static const addToken = '/add-token';
  static const settings = '/settings';
  static const security = '/security';
  static const qrScanner = '/qr-scanner';
  static const history = '/history';
  static const preferences = '/preferences';
  static const fiatCurrencies = '/fiat-currencies';
  static const languages = '/languages';
  static const notificationManagement = '/notificationmanagement';
  static const receive = '/receive';
  static const send = '/send';
  static const sendDetailBase = '/send_detail';
  static String sendDetail(String tokenJson) => '$sendDetailBase/$tokenJson';
  static const dex = '/dex';
  static const dexCreatePool = '/dex-create-pool';
  static const transactionDetail = '/transaction_detail';
  static const walletDetail = '/wallet-detail';
  static const cryptoDetails = '/crypto-details';
  static const receiveWallet = '/receive-wallet';
  static const addAddress = '/add-address';
  static const editAddress = '/edit-address';
  static const priceAlerts = '/notification-center/price-alerts';
  static const securityNotifications = '/notification-center/security';
  static const adminNotifications = '/admin/notifications';

  static const Set<String> publicRoutes = {
    splash,
    importCreate,
    importWallet,
    createNewWallet,
    passcodeSetup,
    passcodeConfirm,
    enterPasscode,
    backup,
    phraseKey,
    phraseKeyConfirm,
  };

  static const Set<String> sensitiveRoutes = {
    enterPasscode,
    passcodeSetup,
    passcodeConfirm,
    backup,
    phraseKey,
    phraseKeyConfirm,
    importWallet,
    createNewWallet,
  };
}
