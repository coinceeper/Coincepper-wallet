# سرویس‌های API برای Flutter

این پوشه شامل تمام سرویس‌های API مورد نیاز برای اپلیکیشن کیف پول ارز دیجیتال است.

## 📁 ساختار فایل‌ها

```
services/
├── api_models.dart          # مدل‌های request و response
├── api_service.dart         # سرویس اصلی API
├── network_manager.dart     # مدیریت شبکه و SSL
├── service_provider.dart    # مدیریت dependency injection
└── README.md              # این فایل
```

## 🚀 شروع کار

### 1. مقداردهی اولیه

```dart
import 'package:my_flutter_app/services/service_provider.dart';

void main() {
  // مقداردهی سرویس‌ها
  ServiceProvider.instance.initialize();
  
  runApp(MyApp());
}
```

### 2. استفاده از API Service

```dart
import 'package:my_flutter_app/services/api_service.dart';
import 'package:my_flutter_app/services/service_provider.dart';

class MyWidget extends StatefulWidget {
  @override
  _MyWidgetState createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final ApiService _apiService = ServiceProvider.instance.apiService;

  Future<void> _createWallet() async {
    try {
      final response = await _apiService.generateWallet('کیف پول من');
      if (response.success) {
        print('کیف پول ایجاد شد: ${response.walletID}');
      }
    } catch (e) {
      print('خطا: $e');
    }
  }
}
```

## Non-custodial (current app)

Wallet create/import, addresses, balances, history, and send run **on-device** via `WalletRepository`, `AddressRegistry`, `OnChainBalanceService`, `HistoryIndexer`, and `LocalSendFacade`.

Custodial APIs (`generateWallet`, `importWallet`, `getBalance`, `getTransactions`, `receiveToken`) throw `UnsupportedError` in `ApiService`.

### Wallet (local)

```dart
import 'package:my_flutter_app/wallet/wallet_repository.dart';

final created = await WalletRepository.instance.createWallet(walletName: 'My wallet');
// Mnemonic stays on device; register public addresses via ApiService.registerPublicAddresses.
```

### 💰 عملیات موجودی و قیمت

#### دریافت قیمت‌ها
```dart
final response = await _apiService.getPrices(
  ['BTC', 'ETH', 'USDT'],
  ['USD', 'EUR']
);
if (response.success) {
  response.prices!.forEach((symbol, prices) {
    print('$symbol: ${prices['USD']?.price}');
  });
}
```

#### Balances (on-chain)

Use `OnChainBalanceService.instance.balancesForActiveTokens(userId, activeTokens)` or `TokenProvider.fetchBalancesForActiveTokens()`.

#### دریافت کارمزد گاز
```dart
final response = await _apiService.getGasFee();
print('Ethereum: ${response.ethereum?.gasFee}');
print('Bitcoin: ${response.bitcoin?.gasFee}');
```

#### دریافت تمام ارزها
```dart
final response = await _apiService.getAllCurrencies();
if (response.success) {
  print('تعداد ارزها: ${response.currencies.length}');
  response.currencies.forEach((currency) {
    print('${currency.symbol} (${currency.currencyName})');
  });
}
```

### 📊 عملیات تراکنش

#### History (indexers)

```dart
final txs = await HistoryIndexer.instance.fetchAndCache(userId);
```

`update-balance` on the server is disabled for non-custodial wallets (HTTP 410). The app does not call it.

### 💸 عملیات ارسال

#### آماده‌سازی تراکنش
```dart
final response = await _apiService.prepareTransaction(
  blockchainName: 'Ethereum',
  senderAddress: '0x123...',
  recipientAddress: '0x456...',
  amount: '0.1'
);
if (response.success) {
  print('Transaction ID: ${response.transactionId}');
  print('کارمزد: ${response.details.estimatedFee}');
}
```

#### تخمین کارمزد
```dart
final response = await _apiService.estimateFee(
  blockchain: 'Ethereum',
  fromAddress: '0x123...',
  toAddress: '0x456...',
  amount: 0.1
);
print('کارمزد: ${response.fee} ${response.feeCurrency}');
print('گزینه‌های اولویت:');
print('  کند: ${response.priorityOptions.slow.fee}');
print('  متوسط: ${response.priorityOptions.average.fee}');
print('  سریع: ${response.priorityOptions.fast.fee}');
```

#### تایید تراکنش
```dart
final response = await _apiService.confirmTransaction(
  transactionId: 'tx_123456789'
);
if (response.success) {
  print('Hash: ${response.transactionHash}');
  print('وضعیت: ${response.status}');
}
```

### 🔔 عملیات اعلان‌ها

#### ثبت دستگاه
```dart
final response = await _apiService.registerDevice(
  userId: 'userID',
  walletId: 'walletID',
  deviceToken: 'device_token',
  deviceName: 'iPhone 12',
  deviceType: 'ios'
);
if (response.success) {
  print('Device ID: ${response.deviceId}');
}
```

### 🤖 عملیات AI

#### ثبت کاربر AI
```dart
final response = await _apiService.registerAIUser(
  userId: 'userID',
  walletId: 'walletID'
);
print('Interaction ID: ${response.interactionId}');
print('وضعیت: ${response.status}');
```

#### ایجاد تعامل جدید
```dart
final response = await _apiService.createNewInteraction(
  userId: 'userID',
  walletId: 'walletID'
);
print('Interaction ID: ${response.interactionId}');
```

## 🌐 مدیریت شبکه

### بررسی اتصال
```dart
final networkManager = ServiceProvider.instance.networkManager;
final isConnected = await networkManager.isConnected();
print('اتصال: ${isConnected ? "متصل" : "قطع"}');
```

### دریافت اطلاعات شبکه
```dart
final networkInfo = await networkManager.getNetworkInfo();
print('نوع اتصال: ${networkInfo['connectionType']}');
print('پلتفرم: ${networkInfo['platform']}');
```

### تست اتصال سرور
```dart
final isServerConnected = await networkManager.testServerConnection();
print('اتصال سرور: ${isServerConnected ? "موفق" : "ناموفق"}');
```

## ⚙️ تنظیمات

### تنظیمات اپلیکیشن
```dart
// در فایل service_provider.dart
class AppConfig {
  static const String apiBaseUrl = 'https://coinceeper.com/api/';
  static const Duration requestTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;
  // ...
}
```

### تنظیمات شبکه
```dart
// در فایل network_manager.dart
class NetworkConfig {
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  // ...
}
```

## 🛠️ مدیریت خطا

### استفاده از ApiResult
```dart
Future<ApiResult<BalanceResponse>> getBalanceSafe(String userId) async {
  try {
    final response = await _apiService.getBalance(userId);
    return ApiResult.success(response);
  } catch (e) {
    return ApiResult.error(AppException(message: e.toString()));
  }
}

// استفاده
final result = await getBalanceSafe('userID');
if (result.isSuccess) {
  print('موجودی: ${result.data?.balances?.length}');
} else {
  print('خطا: ${result.displayMessage}');
}
```



## 🔧 نکات مهم

### 1. مدیریت خطا
همیشه از try-catch استفاده کنید:
```dart
try {
  final response = await _apiService.generateWallet('نام');
  // پردازش پاسخ
} catch (e) {
  // مدیریت خطا
  print('خطا: $e');
}
```

### 2. بررسی اتصال شبکه
قبل از هر درخواست API، اتصال شبکه را بررسی کنید:
```dart
final isConnected = await ServiceProvider.instance.checkNetworkConnection();
if (!isConnected) {
  // نمایش پیام عدم اتصال
  return;
}
```

### 3. مدیریت UserID
UserID به طور خودکار از SharedPreferences خوانده می‌شود:
```dart
// ذخیره UserID
final prefs = await SharedPreferences.getInstance();
await prefs.setString('UserID', 'user123');

// خواندن خودکار در API calls
```

### 4. Logging
تمام درخواست‌ها و پاسخ‌ها در console لاگ می‌شوند:
```
🌐 API Request/Response: POST /api/generate-wallet
🤖 AI API Request/Response: POST /ai-api/users/register
```

## 📦 Dependencies

این سرویس‌ها به پکیج‌های زیر نیاز دارند:

```yaml
dependencies:
  dio: ^5.4.0
  http: ^1.1.0
  shared_preferences: ^2.2.2
  connectivity_plus: ^5.0.2
  json_annotation: ^4.8.1
```



## 📞 پشتیبانی

در صورت بروز مشکل:

1. اتصال شبکه را بررسی کنید
2. URL های API را بررسی کنید
3. Bearer token را بررسی کنید
4. Log ها را در console بررسی کنید
5. با تیم توسعه تماس بگیرید 