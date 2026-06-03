import 'package:json_annotation/json_annotation.dart';
import '../utils/json_converters.dart';

part 'api_models.g.dart';

// ==================== REQUEST MODELS ====================

/// آدرس بلاکچین
@JsonSerializable()
class BlockchainAddress {
  @JsonKey(name: 'BlockchainName')
  final String blockchainName;
  
  @JsonKey(name: 'PublicAddress')
  final String publicAddress;

  BlockchainAddress({required this.blockchainName, required this.publicAddress});

  factory BlockchainAddress.fromJson(Map<String, dynamic> json) => _$BlockchainAddressFromJson(json);
  Map<String, dynamic> toJson() => _$BlockchainAddressToJson(this);
}

/// داده‌های ایمپورت والت
class ImportWalletData {
  @JsonKey(name: 'Addresses')
  final List<BlockchainAddress> addresses;
  @JsonKey(name: 'Mnemonic')
  final String mnemonic;
  @JsonKey(name: 'UserID')
  final String userID;
  @JsonKey(name: 'WalletID')
  final String walletID;

  ImportWalletData({
    required this.addresses,
    required this.mnemonic,
    required this.userID,
    required this.walletID,
  });

  factory ImportWalletData.fromJson(Map<String, dynamic> json) {
    print('🔧 ImportWalletData.fromJson - Parsing JSON:');
    print('   Raw JSON: $json');
    print('   Has Addresses: ${json.containsKey('Addresses')}');
    print('   Has Mnemonic: ${json.containsKey('Mnemonic')}');
    print('   Has UserID: ${json.containsKey('UserID')}');
    print('   Has WalletID: ${json.containsKey('WalletID')}');
    
    final addresses = (json['Addresses'] as List<dynamic>?)
            ?.map((e) => BlockchainAddress.fromJson(e as Map<String, dynamic>))
            .toList() ?? [];
    final mnemonic = json['Mnemonic'] as String? ?? '';
    final userID = json['UserID'] as String? ?? '';
    final walletID = json['WalletID'] as String? ?? '';
    
    print('   Parsed Addresses Count: ${addresses.length}');
    print('   Parsed Mnemonic Length: ${mnemonic.length}');
    print('   Parsed UserID: $userID');
    print('   Parsed WalletID: $walletID');
    
    return ImportWalletData(
      addresses: addresses,
      mnemonic: mnemonic,
      userID: userID,
      walletID: walletID,
    );
  }
  Map<String, dynamic> toJson() => {
    'Addresses': addresses.map((e) => e.toJson()).toList(),
    'Mnemonic': mnemonic,
    'UserID': userID,
    'WalletID': walletID,
  };
}

/// پاسخ ایمپورت والت
@JsonSerializable()
class ImportWalletResponse {
  final ImportWalletData? data;
  final String message;
  final String status;

  ImportWalletResponse({
    this.data,
    required this.message,
    required this.status,
  });

  factory ImportWalletResponse.fromJson(Map<String, dynamic> json) {
    print('🔧 ImportWalletResponse.fromJson - Parsing response:');
    print('   Raw JSON: $json');
    print('   Has Data: ${json.containsKey('data')}');
    print('   Has Message: ${json.containsKey('message')}');
    print('   Has Status: ${json.containsKey('status')}');
    
    final response = _$ImportWalletResponseFromJson(json);
    print('   Parsed Status: ${response.status}');
    print('   Parsed Message: ${response.message}');
    print('   Parsed Data: ${response.data != null}');
    
    return response;
  }
  
  Map<String, dynamic> toJson() => _$ImportWalletResponseToJson(this);
}

/// درخواست برای دریافت قیمت‌ها
@JsonSerializable()
class PricesRequest {
  @JsonKey(name: 'Symbol')
  final List<String> symbol;
  
  @JsonKey(name: 'FiatCurrencies')
  final List<String> fiatCurrencies;

  PricesRequest({required this.symbol, required this.fiatCurrencies}) {
    assert(symbol.isNotEmpty, 'Symbol list cannot be empty');
    assert(fiatCurrencies.isNotEmpty, 'FiatCurrencies list cannot be empty');
  }

  factory PricesRequest.fromJson(Map<String, dynamic> json) => _$PricesRequestFromJson(json);
  Map<String, dynamic> toJson() => _$PricesRequestToJson(this);
}

/// درخواست برای تخمین کارمزد
@JsonSerializable()
class EstimateFeeRequest {
  @JsonKey(name: 'UserID')
  final String userID;
  
  final String blockchain;
  
  @JsonKey(name: 'from_address')
  final String fromAddress;
  
  @JsonKey(name: 'to_address')
  final String toAddress;
  
  final double amount;
  
  final String? type;
  
  @JsonKey(name: 'token_contract')
  final String tokenContract;

  EstimateFeeRequest({
    required this.userID,
    required this.blockchain,
    required this.fromAddress,
    required this.toAddress,
    required this.amount,
    this.type,
    this.tokenContract = '',
  }) {
    assert(userID.isNotEmpty, 'UserID cannot be empty');
    assert(blockchain.isNotEmpty, 'Blockchain cannot be empty');
    assert(fromAddress.isNotEmpty, 'FromAddress cannot be empty');
    assert(toAddress.isNotEmpty, 'ToAddress cannot be empty');
    assert(amount > 0, 'Amount must be greater than 0');
  }

  factory EstimateFeeRequest.fromJson(Map<String, dynamic> json) => _$EstimateFeeRequestFromJson(json);
  Map<String, dynamic> toJson() => _$EstimateFeeRequestToJson(this);
}

/// درخواست برای ثبت دستگاه
@JsonSerializable()
class RegisterDeviceRequest {
  @JsonKey(name: 'UserID')
  final String userId;
  
  @JsonKey(name: 'WalletID')
  final String walletId;
  
  @JsonKey(name: 'DeviceToken')
  final String deviceToken;
  
  @JsonKey(name: 'DeviceName')
  final String deviceName;
  
  @JsonKey(name: 'DeviceType')
  final String deviceType;

  RegisterDeviceRequest({
    required this.userId,
    required this.walletId,
    required this.deviceToken,
    required this.deviceName,
    this.deviceType = 'android',
  }) {
    assert(userId.isNotEmpty, 'UserID cannot be empty');
    assert(walletId.isNotEmpty, 'WalletID cannot be empty');
    assert(deviceToken.isNotEmpty, 'DeviceToken cannot be empty');
    assert(deviceName.isNotEmpty, 'DeviceName cannot be empty');
  }

  factory RegisterDeviceRequest.fromJson(Map<String, dynamic> json) => _$RegisterDeviceRequestFromJson(json);
  Map<String, dynamic> toJson() => _$RegisterDeviceRequestToJson(this);
}

/// درخواست برای دریافت موجودی کاربر (فرمت جدید)
@JsonSerializable()
class GetUserBalanceRequest {
  @JsonKey(name: 'UserID')
  final String userID;
  
  @JsonKey(name: 'CurrencyName')
  final List<String> currencyName;

  GetUserBalanceRequest({
    required this.userID,
    required this.currencyName,
  }) {
    assert(userID.isNotEmpty, 'UserID cannot be empty');
    assert(currencyName.isNotEmpty, 'CurrencyName cannot be empty');
  }

  factory GetUserBalanceRequest.fromJson(Map<String, dynamic> json) => _$GetUserBalanceRequestFromJson(json);
  Map<String, dynamic> toJson() => _$GetUserBalanceRequestToJson(this);
}


// ==================== RESPONSE MODELS ====================

/// داده‌های کیف پول
@JsonSerializable()
class WalletData {
  @JsonKey(name: 'UserID')
  final String? userID;
  
  @JsonKey(name: 'WalletID')
  final String? walletID;
  
  final String? mnemonic;
  
  @JsonKey(name: 'Addresses')
  final List<Address>? addresses;

  const WalletData({
    this.userID,
    this.walletID,
    this.mnemonic,
    this.addresses,
  });

  factory WalletData.fromJson(Map<String, dynamic> json) => _$WalletDataFromJson(json);
  Map<String, dynamic> toJson() => _$WalletDataToJson(this);
}

/// آدرس کیف پول
@JsonSerializable()
class Address {
  @JsonKey(name: 'BlockchainName')
  final String? blockchainName;
  
  @JsonKey(name: 'PublicAddress')
  final String? publicAddress;

  const Address({
    this.blockchainName,
    this.publicAddress,
  });

  factory Address.fromJson(Map<String, dynamic> json) => _$AddressFromJson(json);
  Map<String, dynamic> toJson() => _$AddressToJson(this);
}

/// داده‌های قیمت
@JsonSerializable()
class PriceData {
  @JsonKey(name: 'change_24h')
  final String change24h;
  final String price;

  const PriceData({
    required this.change24h,
    required this.price,
  });

  factory PriceData.fromJson(Map<String, dynamic> json) => _$PriceDataFromJson(json);
  Map<String, dynamic> toJson() => _$PriceDataToJson(this);

  /// Get price as double with safe parsing
  double? get priceAsDouble {
    try {
      // Clean the price string by removing commas, spaces, and other formatting
      final cleanPrice = price.replaceAll(',', '').replaceAll(' ', '').trim();
      final parsed = double.tryParse(cleanPrice);
      if (parsed == null) {
        print('⚠️ ApiPriceData: Failed to parse price "$price" (cleaned: "$cleanPrice")');
      }
      return parsed;
    } catch (e) {
      print('❌ ApiPriceData: Error parsing price "$price": $e');
      return null;
    }
  }

  /// Get 24h change as double with safe parsing
  double? get change24hAsDouble {
    try {
      // Clean the change string by removing %, +, commas, and spaces
      final cleanChange = change24h.replaceAll('%', '').replaceAll('+', '').replaceAll(',', '').replaceAll(' ', '').trim();
      final parsed = double.tryParse(cleanChange);
      if (parsed == null && change24h.isNotEmpty) {
        print('⚠️ ApiPriceData: Failed to parse change24h "$change24h" (cleaned: "$cleanChange")');
      }
      return parsed;
    } catch (e) {
      print('❌ ApiPriceData: Error parsing change24h "$change24h": $e');
      return null;
    }
  }

  /// Market cap (placeholder for future use)
  double? get marketCap => null;

  /// 24h volume (placeholder - not available in this model)
  String? get volume24h => null;

  /// 1h change (placeholder - not available in this model)
  String? get change1h => null;

  /// 7d change (placeholder - not available in this model)
  String? get change7d => null;
}

/// پاسخ قیمت‌ها
@JsonSerializable()
class PricesResponse {
  @BoolIntConverter()
  final bool success;
  final Map<String, Map<String, PriceData>>? prices;

  const PricesResponse({
    required this.success,
    this.prices,
  });

  factory PricesResponse.fromJson(Map<String, dynamic> json) => _$PricesResponseFromJson(json);
  Map<String, dynamic> toJson() => _$PricesResponseToJson(this);
}

/// ارز API
@JsonSerializable()
class ApiCurrency {
  @JsonKey(name: 'CurrencyID')
  final String? currencyId;
  
  @JsonKey(name: 'BlockchainName')
  final String? blockchainName;
  
  @JsonKey(name: 'CurrencyName')
  final String? currencyName;
  
  @JsonKey(name: 'Symbol')
  final String? symbol;
  
  @JsonKey(name: 'Icon')
  final String? icon;
  
  @JsonKey(name: 'SmartContractAddress')
  final String? smartContractAddress;
  
  @JsonKey(name: 'IsToken')
  @NullableBoolIntConverter()
  final bool? isToken;
  
  @JsonKey(name: 'DecimalPlaces')
  final int? decimalPlaces;

  const ApiCurrency({
    this.currencyId,
    this.blockchainName,
    this.currencyName,
    this.symbol,
    this.icon,
    this.smartContractAddress,
    this.isToken,
    this.decimalPlaces,
  });

  factory ApiCurrency.fromJson(Map<String, dynamic> json) => _$ApiCurrencyFromJson(json);
  Map<String, dynamic> toJson() => _$ApiCurrencyToJson(this);
}

/// پاسخ API عمومی
@JsonSerializable()
class ApiResponse {
  final List<ApiCurrency> currencies;
  @BoolIntConverter()
  final bool success;

  const ApiResponse({
    required this.currencies,
    required this.success,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json) => _$ApiResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ApiResponseToJson(this);
}

/// آیتم موجودی
@JsonSerializable()
class BalanceItem {
  @JsonKey(name: 'balance')
  final String? balance;
  
  @JsonKey(name: 'blockchain')
  final String? blockchain;
  
  @JsonKey(name: 'is_token')
  @NullableBoolIntConverter()
  final bool? isToken;
  
  @JsonKey(name: 'symbol')
  final String? symbol;
  
  @JsonKey(name: 'currency_name')
  final String? currencyName;

  const BalanceItem({
    this.balance,
    this.blockchain,
    this.isToken,
    this.symbol,
    this.currencyName,
  });

  /// سفارشی: پشتیبانی از هر دو فرمت کلیدها (lowercase و UpperCamelCase)
  factory BalanceItem.fromJson(Map<String, dynamic> json) {
    final dynamic rawBalance = json['balance'] ?? json['Balance'];
    final dynamic rawBlockchain = json['blockchain'] ?? json['Blockchain'];
    final dynamic rawIsToken = json['is_token'] ?? json['IsToken'];
    final dynamic rawSymbol = json['symbol'] ?? json['Symbol'];
    final dynamic rawCurrencyName = json['currency_name'] ?? json['CurrencyName'];

    bool? parsedIsToken;
    if (rawIsToken is bool) {
      parsedIsToken = rawIsToken;
    } else if (rawIsToken is int) {
      parsedIsToken = rawIsToken != 0;
    } else if (rawIsToken is String) {
      final v = rawIsToken.toLowerCase();
      parsedIsToken = v == 'true' || v == '1';
    }

    return BalanceItem(
      balance: rawBalance?.toString(),
      blockchain: rawBlockchain?.toString(),
      isToken: parsedIsToken,
      symbol: rawSymbol?.toString(),
      currencyName: rawCurrencyName?.toString(),
    );
  }

  Map<String, dynamic> toJson() => _$BalanceItemToJson(this);
}

/// پاسخ موجودی کاربر (فرمت جدید)
@JsonSerializable()
class GetUserBalanceResponse {
  @JsonKey(name: 'Tokens')
  final Map<String, dynamic> tokens;
  
  @JsonKey(name: 'UserID')
  final String userID;
  
  @BoolIntConverter()
  final bool success;

  const GetUserBalanceResponse({
    required this.tokens,
    required this.userID,
    required this.success,
  });

  factory GetUserBalanceResponse.fromJson(Map<String, dynamic> json) => _$GetUserBalanceResponseFromJson(json);
  Map<String, dynamic> toJson() => _$GetUserBalanceResponseToJson(this);
}

/// آیتم کارمزد گاز
@JsonSerializable()
class GasFeeItem {
  @JsonKey(name: 'gas_fee')
  final String? gasFee;

  const GasFeeItem({this.gasFee});

  factory GasFeeItem.fromJson(Map<String, dynamic> json) => _$GasFeeItemFromJson(json);
  Map<String, dynamic> toJson() => _$GasFeeItemToJson(this);
}

/// پاسخ کارمزد گاز
@JsonSerializable()
class GasFeeResponse {
  final GasFeeItem? arbitrum;
  final GasFeeItem? avalanche;
  final GasFeeItem? binance;
  final GasFeeItem? bitcoin;
  final GasFeeItem? cardano;
  final GasFeeItem? cosmos;
  final GasFeeItem? ethereum;
  final GasFeeItem? fantom;
  final GasFeeItem? optimism;
  final GasFeeItem? polkadot;
  final GasFeeItem? polygon;
  final GasFeeItem? solana;
  final GasFeeItem? tron;
  final GasFeeItem? xrp;

  const GasFeeResponse({
    this.arbitrum,
    this.avalanche,
    this.binance,
    this.bitcoin,
    this.cardano,
    this.cosmos,
    this.ethereum,
    this.fantom,
    this.optimism,
    this.polkadot,
    this.polygon,
    this.solana,
    this.tron,
    this.xrp,
  });

  factory GasFeeResponse.fromJson(Map<String, dynamic> json) => _$GasFeeResponseFromJson(json);
  Map<String, dynamic> toJson() => _$GasFeeResponseToJson(this);
}

/// کلاس تراکنش
@JsonSerializable()
class Transaction {
  final String? txHash;
  final String? from;
  final String? to;
  final String? amount;
  
  @JsonKey(name: 'tokenSymbol')
  final String? tokenSymbol;
  final String? direction;
  final String? status;
  final String? timestamp;
  
  @JsonKey(name: 'blockchainName')
  final String? blockchainName;
  
  @JsonKey(name: 'price', fromJson: _priceFromJson)
  final double? price;
  
  @JsonKey(name: 'temporaryId')
  final String? temporaryId;

  @JsonKey(name: 'explorerUrl')
  final String? explorerUrl;

  final String? fee;
  final String? assetType;
  final String? tokenContract;

  const Transaction({
    this.txHash,
    this.from,
    this.to,
    this.amount,
    this.tokenSymbol,
    this.direction,
    this.status,
    this.timestamp,
    this.blockchainName,
    this.price,
    this.temporaryId,
    this.explorerUrl,
    this.fee,
    this.assetType,
    this.tokenContract,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) => _$TransactionFromJson(json);
  Map<String, dynamic> toJson() => _$TransactionToJson(this);
  
  /// تبدیل امن String به double برای فیلد price
  static double? _priceFromJson(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.tryParse(value);
      } catch (e) {
        print('⚠️ Warning: Could not parse price value "$value" to double');
        return null;
      }
    }
    print('⚠️ Warning: Unexpected price value type: ${value.runtimeType}');
    return null;
  }
}

/// پاسخ تراکنش‌ها
@JsonSerializable()
class TransactionsResponse {
  final int count;
  final int page;
  
  @JsonKey(name: 'per_page')
  final int perPage;
  final String status;
  final List<Transaction> transactions;

  const TransactionsResponse({
    required this.count,
    required this.page,
    required this.perPage,
    required this.status,
    required this.transactions,
  });

  factory TransactionsResponse.fromJson(Map<String, dynamic> json) => _$TransactionsResponseFromJson(json);
  Map<String, dynamic> toJson() => _$TransactionsResponseToJson(this);
}

/// جزئیات تراکنش
@JsonSerializable()
class TransactionDetails {
  final String amount;
  final String blockchain;
  
  @JsonKey(name: 'estimated_fee')
  final String estimatedFee;
  
  @JsonKey(name: 'explorer_url')
  final String explorerUrl;
  final String recipient;
  final String sender;
  
  @JsonKey(name: 'sender_balance_after')
  final String senderBalanceAfter;
  
  @JsonKey(name: 'sender_balance_before')
  final String senderBalanceBefore;

  const TransactionDetails({
    required this.amount,
    required this.blockchain,
    required this.estimatedFee,
    required this.explorerUrl,
    required this.recipient,
    required this.sender,
    required this.senderBalanceAfter,
    required this.senderBalanceBefore,
  });

  factory TransactionDetails.fromJson(Map<String, dynamic> json) => _$TransactionDetailsFromJson(json);
  Map<String, dynamic> toJson() => _$TransactionDetailsToJson(this);
}

/// پاسخ آماده‌سازی تراکنش
@JsonSerializable()
class PrepareTransactionResponse {
  final TransactionDetails details;
  
  @JsonKey(name: 'expires_at')
  final String expiresAt;
  final String message;
  @BoolIntConverter()
  final bool success;
  
  @JsonKey(name: 'transaction_id')
  final String transactionId;

  const PrepareTransactionResponse({
    required this.details,
    required this.expiresAt,
    required this.message,
    required this.success,
    required this.transactionId,
  });

  factory PrepareTransactionResponse.fromJson(Map<String, dynamic> json) => _$PrepareTransactionResponseFromJson(json);
  Map<String, dynamic> toJson() => _$PrepareTransactionResponseToJson(this);
}

/// گزینه اولویت
@JsonSerializable()
class PriorityOption {
  final int? fee;
  
  @JsonKey(name: 'fee_eth')
  final double? feeEth;

  const PriorityOption({
    this.fee,
    this.feeEth,
  });

  factory PriorityOption.fromJson(Map<String, dynamic> json) => _$PriorityOptionFromJson(json);
  Map<String, dynamic> toJson() => _$PriorityOptionToJson(this);
}

/// گزینه‌های اولویت
@JsonSerializable()
class PriorityOptions {
  final PriorityOption? average;
  final PriorityOption? fast;
  final PriorityOption? slow;

  const PriorityOptions({
    this.average,
    this.fast,
    this.slow,
  });

  factory PriorityOptions.fromJson(Map<String, dynamic> json) => _$PriorityOptionsFromJson(json);
  Map<String, dynamic> toJson() => _$PriorityOptionsToJson(this);
}

/// پاسخ تخمین کارمزد
@JsonSerializable()
class EstimateFeeResponse {
  final int? fee;
  
  @JsonKey(name: 'fee_currency')
  final String? feeCurrency;
  
  @JsonKey(name: 'gas_price')
  final int? gasPrice;
  
  @JsonKey(name: 'gas_used')
  final int? gasUsed;
  
  @JsonKey(name: 'priority_options')
  final PriorityOptions? priorityOptions;
  final int? timestamp;
  final String? unit;
  
  @JsonKey(name: 'usd_price')
  final double? usdPrice;

  const EstimateFeeResponse({
    this.fee,
    this.feeCurrency,
    this.gasPrice,
    this.gasUsed,
    this.priorityOptions,
    this.timestamp,
    this.unit,
    this.usdPrice,
  });

  factory EstimateFeeResponse.fromJson(Map<String, dynamic> json) => _$EstimateFeeResponseFromJson(json);
  Map<String, dynamic> toJson() => _$EstimateFeeResponseToJson(this);
}

/// پاسخ ثبت دستگاه
@JsonSerializable()
class RegisterDeviceResponse {
  @BoolIntConverter()
  final bool success;
  final String? message;
  
  @JsonKey(name: 'deviceId')
  final String? deviceId;

  const RegisterDeviceResponse({
    required this.success,
    this.message,
    this.deviceId,
  });

  factory RegisterDeviceResponse.fromJson(Map<String, dynamic> json) => _$RegisterDeviceResponseFromJson(json);
  Map<String, dynamic> toJson() => _$RegisterDeviceResponseToJson(this);
}

/// پاسخ تایید تراکنش
@JsonSerializable()
class ConfirmTransactionResponse {
  @NullableBoolIntConverter()
  final bool? success;
  final String? message;
  
  @JsonKey(name: 'transaction_hash')
  final String? transactionHash;
  
  @JsonKey(name: 'tx_hash')
  final String? txHash;
  
  final String? status;
  final String? description;

  const ConfirmTransactionResponse({
    this.success,
    this.message,
    this.transactionHash,
    this.txHash,
    this.status,
    this.description,
  });

  factory ConfirmTransactionResponse.fromJson(Map<String, dynamic> json) => _$ConfirmTransactionResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ConfirmTransactionResponseToJson(this);
  
  // Helper method to check if transaction was successful
  bool get isSuccess => success == true || 
                        message == "Transaction sent successfully" || 
                        status == "sent" ||
                        (transactionHash != null && transactionHash!.isNotEmpty) ||
                        (txHash != null && txHash!.isNotEmpty);
  
  // Helper method to get transaction hash
  String? get hash => transactionHash ?? txHash;
}



// ==================== UTILITY CLASSES ====================

/// کلاس برای مدیریت نتایج API
class ApiResult<T> {
  @BoolIntConverter()
  final bool success;
  final T? data;
  final String? error;

  ApiResult.success(this.data) : success = true, error = null;
  ApiResult.error(this.error) : success = false, data = null;
}

// ==================== NOTIFICATION MODELS ====================

/// Firebase notification payload
@JsonSerializable()
class NotificationPayload {
  final String title;
  final String body;

  const NotificationPayload({
    required this.title,
    required this.body,
  });

  factory NotificationPayload.fromJson(Map<String, dynamic> json) => _$NotificationPayloadFromJson(json);
  Map<String, dynamic> toJson() => _$NotificationPayloadToJson(this);
}

/// Transaction notification data
@JsonSerializable()
class NotificationData {
  @JsonKey(name: 'transaction_id')
  final String? transactionId;
  
  final String? type; // "receive", "send", etc.
  final String? direction; // "inbound", "outbound"
  final String? amount;
  final String? currency; // BTC, ETH, etc.
  final String? symbol; // For backward compatibility
  
  @JsonKey(name: 'from_address')
  final String? fromAddress;
  
  @JsonKey(name: 'to_address')
  final String? toAddress;
  
  @JsonKey(name: 'wallet_id')
  final String? walletId;
  
  final String? timestamp;
  final String? status;

  const NotificationData({
    this.transactionId,
    this.type,
    this.direction,
    this.amount,
    this.currency,
    this.symbol,
    this.fromAddress,
    this.toAddress,
    this.walletId,
    this.timestamp,
    this.status,
  });

  factory NotificationData.fromJson(Map<String, dynamic> json) => _$NotificationDataFromJson(json);
  Map<String, dynamic> toJson() => _$NotificationDataToJson(this);
}

/// Android-specific notification configuration
@JsonSerializable()
class AndroidNotificationConfig {
  @JsonKey(name: 'channel_id')
  final String? channelId;
  
  final String? sound;
  final String? icon;
  final int? priority;

  const AndroidNotificationConfig({
    this.channelId,
    this.sound,
    this.icon,
    this.priority,
  });

  factory AndroidNotificationConfig.fromJson(Map<String, dynamic> json) => _$AndroidNotificationConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AndroidNotificationConfigToJson(this);
}

/// Complete FCM notification message
@JsonSerializable()
class FCMNotificationMessage {
  final NotificationPayload notification;
  final NotificationData data;
  
  @JsonKey(name: 'android')
  final Map<String, AndroidNotificationConfig>? androidConfig;

  const FCMNotificationMessage({
    required this.notification,
    required this.data,
    this.androidConfig,
  });

  factory FCMNotificationMessage.fromJson(Map<String, dynamic> json) => _$FCMNotificationMessageFromJson(json);
  Map<String, dynamic> toJson() => _$FCMNotificationMessageToJson(this);
}

// Helper methods for creating notification messages
extension FCMNotificationMessageExtensions on FCMNotificationMessage {
  /// Create a receive notification
  static FCMNotificationMessage createReceiveNotification({
    required String amount,
    required String currency,
    required String fromAddress,
    required String toAddress,
    required String transactionId,
    required String walletId,
  }) {
    return FCMNotificationMessage(
      notification: NotificationPayload(
        title: '💰 Received: $amount $currency',
        body: 'From ${fromAddress.length > 10 ? "${fromAddress.substring(0, 6)}...${fromAddress.substring(fromAddress.length - 4)}" : fromAddress}',
      ),
      data: NotificationData(
        transactionId: transactionId,
        type: 'receive',
        direction: 'inbound',
        amount: amount,
        currency: currency,
        symbol: currency, // For backward compatibility
        fromAddress: fromAddress,
        toAddress: toAddress,
        walletId: walletId,
        timestamp: DateTime.now().toIso8601String(),
        status: 'confirmed',
      ),
      androidConfig: {
        'notification': const AndroidNotificationConfig(
          channelId: 'receive_channel',
          sound: 'receive_sound',
          icon: 'ic_notification',
          priority: 2, // High priority
        ),
      },
    );
  }

  /// Create a send notification
  static FCMNotificationMessage createSendNotification({
    required String amount,
    required String currency,
    required String fromAddress,
    required String toAddress,
    required String transactionId,
    required String walletId,
  }) {
    return FCMNotificationMessage(
      notification: NotificationPayload(
        title: '📤 Sent: $amount $currency',
        body: 'To ${toAddress.length > 10 ? "${toAddress.substring(0, 6)}...${toAddress.substring(toAddress.length - 4)}" : toAddress}',
      ),
      data: NotificationData(
        transactionId: transactionId,
        type: 'send',
        direction: 'outbound',
        amount: amount,
        currency: currency,
        symbol: currency, // For backward compatibility
        fromAddress: fromAddress,
        toAddress: toAddress,
        walletId: walletId,
        timestamp: DateTime.now().toIso8601String(),
        status: 'confirmed',
      ),
      androidConfig: {
        'notification': const AndroidNotificationConfig(
          channelId: 'send_channel',
          sound: 'send_sound',
          icon: 'ic_notification',
          priority: 2, // High priority
        ),
      },
    );
  }
}

// ==================== V2 NOTIFICATION MODELS (Cache Proxy) ====================

/// پاسخ کامل V2 Notification endpoint
/// GET /api/v2/notifications?addresses=0xabc,0xdef
class V2NotificationResponse {
  final bool success;
  final int addressesCount;
  final List<V2NotificationTx> txs;
  final Map<String, int> lastScanned;

  V2NotificationResponse({
    required this.success,
    this.addressesCount = 0,
    required this.txs,
    this.lastScanned = const {},
  });

  factory V2NotificationResponse.fromJson(Map<String, dynamic> json) {
    final rawTxs = (json['txs'] as List<dynamic>? ?? []);
    final rawScanned = (json['last_scanned'] as Map<String, dynamic>? ?? {});
    return V2NotificationResponse(
      success: json['success'] as bool? ?? false,
      addressesCount: (json['addresses_count'] as num?)?.toInt() ?? 0,
      txs: rawTxs
          .map((e) => V2NotificationTx.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastScanned: rawScanned.map(
        (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
      ),
    );
  }
}

/// پاسخ V2 Health endpoint
/// GET /api/v2/health
class V2HealthResponse {
  final bool status;
  final Map<String, dynamic> notifications;
  final Map<String, dynamic>? scanners;

  V2HealthResponse({
    required this.status,
    this.notifications = const {},
    this.scanners,
  });

  factory V2HealthResponse.fromJson(Map<String, dynamic> json) {
    return V2HealthResponse(
      status: json['status'] as bool? ?? false,
      notifications: (json['notifications'] as Map<String, dynamic>? ?? {}),
      scanners: json['scanners'] as Map<String, dynamic>?,
    );
  }

  int get activeAddresses =>
      (notifications['active_addresses'] as num?)?.toInt() ?? 0;
  int get cachedTransactions =>
      (notifications['cached_transactions'] as num?)?.toInt() ?? 0;
  int get lastScannedEth =>
      (notifications['last_scanned_eth'] as num?)?.toInt() ?? 0;
}

/// مدل داده تراکنش دریافتی از V2 Notification endpoint
class V2NotificationTx {
  final String hash;
  final String address;
  final String blockchain;
  final int blockNumber;
  final int timestamp;
  final String direction; // "inbound" or "outbound"
  final String amount; // e.g. "0.5"
  final String tokenSymbol; // e.g. "ETH", "BTC", "USDT"
  final String from; // sender address
  final String to; // receiver address

  V2NotificationTx({
    required this.hash,
    required this.address,
    required this.blockchain,
    this.blockNumber = 0,
    this.timestamp = 0,
    this.direction = '',
    this.amount = '',
    this.tokenSymbol = '',
    this.from = '',
    this.to = '',
  });

  factory V2NotificationTx.fromJson(Map<String, dynamic> json) {
    return V2NotificationTx(
      hash: json['hash']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      blockchain: json['blockchain']?.toString() ?? '',
      blockNumber: (json['blockNumber'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      direction: json['direction']?.toString() ?? '',
      amount: json['amount']?.toString() ?? '',
      tokenSymbol: json['tokenSymbol']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
    );
  }

  String get shortHash =>
      hash.length > 12 ? '${hash.substring(0, 6)}...${hash.substring(hash.length - 4)}' : hash;
  String get shortAddress =>
      address.length > 12 ? '${address.substring(0, 6)}...${address.substring(address.length - 4)}' : address;
}

/// کلاس برای مدیریت خطاهای API
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AppException({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'AppException: $message (Code: $code)';
} 