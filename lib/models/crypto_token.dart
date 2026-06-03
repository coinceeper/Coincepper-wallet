import 'package:json_annotation/json_annotation.dart';
import '../utils/json_converters.dart';

part 'crypto_token.g.dart';

@JsonSerializable()
class CryptoToken {
  final String? name;
  final String? symbol;
  @JsonKey(name: 'BlockchainName')
  final String? blockchainName;
  @JsonKey(name: 'iconUrl')
  final String? iconUrl;
  @JsonKey(name: 'isEnabled')
  @BoolIntConverter()
  final bool isEnabled;
  @JsonKey(name: 'amount')
  final double amount;
  @JsonKey(name: 'isToken')
  @BoolIntConverter()
  final bool isToken;
  @JsonKey(name: 'SmartContractAddress')
  final String? smartContractAddress;

  const CryptoToken({
    this.name,
    this.symbol,
    this.blockchainName,
    this.iconUrl = "https://coinceeper.com/defaultIcons/coin.png",
    required this.isEnabled,
    this.amount = 0.0,
    required this.isToken,
    this.smartContractAddress,
  });

  factory CryptoToken.fromJson(Map<String, dynamic> json) => _$CryptoTokenFromJson(json);
  Map<String, dynamic> toJson() => _$CryptoTokenToJson(this);

  CryptoToken copyWith({
    String? name,
    String? symbol,
    String? blockchainName,
    String? iconUrl,
    bool? isEnabled,
    double? amount,
    bool? isToken,
    String? smartContractAddress,
  }) {
    return CryptoToken(
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      blockchainName: blockchainName ?? this.blockchainName,
      iconUrl: iconUrl ?? this.iconUrl,
      isEnabled: isEnabled ?? this.isEnabled,
      amount: amount ?? this.amount,
      isToken: isToken ?? this.isToken,
      smartContractAddress: smartContractAddress ?? this.smartContractAddress,
    );
  }

  @override
  String toString() {
    return 'CryptoToken(name: $name, symbol: $symbol, blockchainName: $blockchainName, iconUrl: $iconUrl, isEnabled: $isEnabled, amount: $amount, isToken: $isToken, smartContractAddress: $smartContractAddress)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CryptoToken &&
        other.name == name &&
        other.symbol == symbol &&
        other.blockchainName == blockchainName &&
        other.iconUrl == iconUrl &&
        other.isEnabled == isEnabled &&
        other.amount == amount &&
        other.isToken == isToken &&
        other.smartContractAddress == smartContractAddress;
  }

  @override
  int get hashCode {
    return name.hashCode ^
        symbol.hashCode ^
        blockchainName.hashCode ^
        iconUrl.hashCode ^
        isEnabled.hashCode ^
        amount.hashCode ^
        isToken.hashCode ^
        smartContractAddress.hashCode;
  }
}

@JsonSerializable()
class Asset {
  final int icon;
  final String name;
  @JsonKey(name: 'BlockchainName')
  final String blockchainName;
  final String amount;
  final String value;

  const Asset({
    required this.icon,
    required this.name,
    required this.blockchainName,
    required this.amount,
    required this.value,
  });

  factory Asset.fromJson(Map<String, dynamic> json) => _$AssetFromJson(json);
  Map<String, dynamic> toJson() => _$AssetToJson(this);

  Asset copyWith({
    int? icon,
    String? name,
    String? blockchainName,
    String? amount,
    String? value,
  }) {
    return Asset(
      icon: icon ?? this.icon,
      name: name ?? this.name,
      blockchainName: blockchainName ?? this.blockchainName,
      amount: amount ?? this.amount,
      value: value ?? this.value,
    );
  }

  @override
  String toString() {
    return 'Asset(icon: $icon, name: $name, blockchainName: $blockchainName, amount: $amount, value: $value)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Asset &&
        other.icon == icon &&
        other.name == name &&
        other.blockchainName == blockchainName &&
        other.amount == amount &&
        other.value == value;
  }

  @override
  int get hashCode {
    return icon.hashCode ^
        name.hashCode ^
        blockchainName.hashCode ^
        amount.hashCode ^
        value.hashCode;
  }
}

@JsonSerializable()
class SettingItemData {
  final int icon;
  final String title;
  final String? subtitle;

  const SettingItemData({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  factory SettingItemData.fromJson(Map<String, dynamic> json) => _$SettingItemDataFromJson(json);
  Map<String, dynamic> toJson() => _$SettingItemDataToJson(this);

  SettingItemData copyWith({
    int? icon,
    String? title,
    String? subtitle,
  }) {
    return SettingItemData(
      icon: icon ?? this.icon,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
    );
  }

  @override
  String toString() {
    return 'SettingItemData(icon: $icon, title: $title, subtitle: $subtitle)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingItemData &&
        other.icon == icon &&
        other.title == title &&
        other.subtitle == subtitle;
  }

  @override
  int get hashCode {
    return icon.hashCode ^
        title.hashCode ^
        subtitle.hashCode;
  }
}

@JsonSerializable()
class WalletResponse {
  final bool success;
  @JsonKey(name: 'PhraseKey')
  final String? phraseKey;
  final String? message;

  const WalletResponse({
    required this.success,
    this.phraseKey,
    this.message,
  });

  factory WalletResponse.fromJson(Map<String, dynamic> json) => _$WalletResponseFromJson(json);
  Map<String, dynamic> toJson() => _$WalletResponseToJson(this);

  WalletResponse copyWith({
    bool? success,
    String? phraseKey,
    String? message,
  }) {
    return WalletResponse(
      success: success ?? this.success,
      phraseKey: phraseKey ?? this.phraseKey,
      message: message ?? this.message,
    );
  }

  @override
  String toString() {
    return 'WalletResponse(success: $success, phraseKey: $phraseKey, message: $message)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WalletResponse &&
        other.success == success &&
        other.phraseKey == phraseKey &&
        other.message == message;
  }

  @override
  int get hashCode {
    return success.hashCode ^
        phraseKey.hashCode ^
        message.hashCode;
  }
} 