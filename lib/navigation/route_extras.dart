/// Typed route extras (no secrets).
class SendRouteExtra {
  const SendRouteExtra({this.qrArguments});
  final Map<String, dynamic>? qrArguments;

  static SendRouteExtra? from(Object? extra) {
    if (extra is SendRouteExtra) return extra;
    if (extra is Map<String, dynamic>) {
      return SendRouteExtra(qrArguments: extra);
    }
    return null;
  }
}

class QrScannerExtra {
  const QrScannerExtra({this.returnScreen = 'home'});
  final String returnScreen;

  static QrScannerExtra from(Object? extra) {
    if (extra is QrScannerExtra) return extra;
    if (extra is Map<String, dynamic>) {
      return QrScannerExtra(
        returnScreen: extra['returnScreen'] as String? ?? 'home',
      );
    }
    return const QrScannerExtra();
  }
}

class BackupRouteExtra {
  const BackupRouteExtra({
    required this.walletName,
    this.userId,
    this.walletId,
    this.isPasscodeEnabled = false,
    this.skipPhraseKey = false,
  });

  final String walletName;
  final String? userId;
  final String? walletId;
  final bool isPasscodeEnabled;
  final bool skipPhraseKey;

  static BackupRouteExtra? from(Object? extra) {
    if (extra is BackupRouteExtra) return extra;
    if (extra is Map<String, dynamic>) {
      return BackupRouteExtra(
        walletName: extra['walletName'] as String? ?? 'Unknown Wallet',
        userId: extra['userID'] as String?,
        walletId: extra['walletID'] as String?,
        isPasscodeEnabled: extra['isPasscodeEnabled'] as bool? ?? false,
        skipPhraseKey: extra['skipPhraseKey'] as bool? ?? false,
      );
    }
    return null;
  }
}

class CryptoDetailsExtra {
  const CryptoDetailsExtra({
    required this.tokenName,
    required this.tokenSymbol,
    required this.iconUrl,
    required this.isToken,
    required this.blockchainName,
    this.gasFee = 0.0,
  });

  final String tokenName;
  final String tokenSymbol;
  final String iconUrl;
  final bool? isToken;
  final String blockchainName;
  final double gasFee;

  static CryptoDetailsExtra? from(Object? extra) {
    if (extra is CryptoDetailsExtra) return extra;
    if (extra is Map<String, dynamic>) {
      return CryptoDetailsExtra(
        tokenName: extra['tokenName'] as String? ?? '',
        tokenSymbol: extra['tokenSymbol'] as String? ?? '',
        iconUrl: extra['iconUrl'] as String? ?? '',
        isToken: extra['isToken'] as bool?,
        blockchainName: extra['blockchainName'] as String? ?? '',
        gasFee: (extra['gasFee'] as num?)?.toDouble() ?? 0.0,
      );
    }
    return null;
  }
}

class ReceiveWalletExtra {
  const ReceiveWalletExtra({
    required this.cryptoName,
    required this.blockchainName,
    required this.address,
    required this.symbol,
  });

  final String cryptoName;
  final String blockchainName;
  final String address;
  final String symbol;

  static ReceiveWalletExtra? from(Object? extra) {
    if (extra is ReceiveWalletExtra) return extra;
    if (extra is Map<String, dynamic>) {
      return ReceiveWalletExtra(
        cryptoName: extra['cryptoName'] as String? ?? '',
        blockchainName: extra['blockchainName'] as String? ?? '',
        address: extra['address'] as String? ?? '',
        symbol: extra['symbol'] as String? ?? '',
      );
    }
    return null;
  }
}

class TransactionDetailExtra {
  const TransactionDetailExtra({this.transactionId});
  final String? transactionId;

  static TransactionDetailExtra? from(Object? extra) {
    if (extra is TransactionDetailExtra) return extra;
    if (extra is Map<String, dynamic>) {
      return TransactionDetailExtra(
        transactionId: extra['transactionId'] as String?,
      );
    }
    return null;
  }
}

class PasscodeRouteExtra {
  const PasscodeRouteExtra({
    this.walletName,
    this.firstPasscode,
    this.isFromBackground = false,
  });

  final String? walletName;
  final String? firstPasscode;
  final bool isFromBackground;

  static PasscodeRouteExtra? from(Object? extra) {
    if (extra is PasscodeRouteExtra) return extra;
    if (extra is Map<String, dynamic>) {
      return PasscodeRouteExtra(
        walletName: extra['walletName'] as String?,
        firstPasscode: extra['firstPasscode'] as String?,
        isFromBackground: extra['isFromBackground'] as bool? ?? false,
      );
    }
    return null;
  }
}

