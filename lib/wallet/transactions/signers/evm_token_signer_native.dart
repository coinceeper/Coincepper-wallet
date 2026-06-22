import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;
import 'package:wallet_core_bindings/wallet_core_bindings.dart';
import 'package:web3dart/web3dart.dart';

import '../../../services/sensitive_data.dart';
import '../../core/wallet_core_bridge.dart';
import '../../core/wallet_core_coin_map.dart';
import '../../core/wallet_core_config.dart';
import '../../tokens/token_metadata_service.dart';
import '../signed_transaction_data.dart';
import '../../../di/service_locator.dart';
import '../../../utils/secure_log.dart';

/// ERC20/BEP20 transfer using private key from Wallet Core.
///
/// ## 🛡️ Double-Spend Prevention
///
/// Broadcasting an already-signed raw transaction is **idempotent**.
/// This class signs once and retries broadcast only, using the same signed
/// bytes on each attempt. This eliminates the double-spend risk present when
/// the entire sign+broadcast flow is retried.
///
/// ## امنیت حافظه
///
/// - کلید خصوصی به صورت `TWPrivateKey` (C++ native) استخراج می‌شود
/// - `priv.data` به `Uint8List` تبدیل و مستقیماً برای تولید هگز استفاده می‌شود
/// - پس از ساخت `EthPrivateKey`، native key حذف و بایت‌ها با `secureWipe()` پاک می‌شوند
/// - هگز رشته موقتاً در Dart heap می‌ماند (محدودیت web3dart)
class EvmTokenSigner {
  static const _maxBroadcastRetries = 3;

  Future<String?> sendErc20({
    required String mnemonic,
    required String blockchainName,
    required String senderAddress,
    required String contractAddress,
    required String recipient,
    required String amount,
    String tokenSymbol = '',
    void Function(SignedTransactionData)? onSigned,
  }) async {
    final wallet = ServiceLocator.get<WalletCoreBridge>().openWallet(mnemonic);
    try {
      final coin = WalletCoreCoinMap.coinTypeForBlockchain(blockchainName) ??
          TWCoinType.Ethereum;
      final priv = wallet.getKeyForCoin(coin);
      final privData = priv.data;
      // 🛡️ ساخت EthPrivateKey از بایت‌ها با حداقل طول عمر هگز در حافظه
      final hexKey = HEX.encode(privData);
      final credentials = EthPrivateKey.fromHex(hexKey);
      // 🛡️ پاکسازی فوری: native key و Dart copy
      priv.delete();
      privData.secureWipe();

      final rpc = WalletCoreConfig.evmRpcForBlockchain(blockchainName);
      final client = Web3Client(rpc, http.Client());
      try {
        final contract = DeployedContract(
          ContractAbi.fromJson(
            '[{"constant":false,"inputs":[{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"type":"function"}]',
            'ERC20',
          ),
          EthereumAddress.fromHex(contractAddress),
        );
        final fn = contract.function('transfer');
        final decimals = await ServiceLocator.get<TokenMetadataService>().decimalsForToken(
          blockchainName: blockchainName,
          contractAddress: contractAddress,
          symbol: tokenSymbol,
        );
        final value = _parseTokenAmount(amount, decimals);
        final to = EthereumAddress.fromHex(
          recipient.startsWith('0x') ? recipient : '0x$recipient',
        );
        final tx = Transaction.callContract(
          contract: contract,
          function: fn,
          parameters: [to, value],
        );
        // 🛡️ Sign once — deterministic signed raw transaction
        final chainId = await _chainId(client, blockchainName);
        final signedTx = await client.signTransaction(credentials, tx, chainId: chainId);
        final signedTxHex = HEX.encode(signedTx);
        // 🛡️ Store signed tx for idempotent retry before broadcasting
        onSigned?.call(SignedTransactionData(
          rawData: signedTxHex,
          chainLabel: 'EVM',
          blockchainName: blockchainName,
        ));
        // 🛡️ Idempotent broadcast: same signedTx on each retry
        for (var i = 0; i < _maxBroadcastRetries; i++) {
          try {
            final txHash = await client.sendRawTransaction(signedTx);
            return txHash;
          } catch (e) {
            if (i == _maxBroadcastRetries - 1) rethrow;
            SecureLog.i('ERC20 broadcast retry ${i + 1}/$_maxBroadcastRetries '
                '(same signed tx — idempotent, no double-spend risk)');
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        }
        throw StateError('ERC20 broadcast failed after $_maxBroadcastRetries attempts');
      } finally {
        client.dispose();
      }
    } finally {
      wallet.delete();
    }
  }

  BigInt _parseTokenAmount(String amount, int decimals) {
    final parts = amount.split('.');
    final whole = BigInt.parse(parts[0]);
    var frac = BigInt.zero;
    if (parts.length > 1) {
      final f = parts[1].padRight(decimals, '0').substring(0, decimals);
      frac = BigInt.parse(f);
    }
    return whole * BigInt.from(10).pow(decimals) + frac;
  }

  Future<int> _chainId(Web3Client client, String name) async {
    try {
      final id = await client.getChainId();
      return id.toInt();
    } catch (e) {
      SecureLog.w('EvmTokenSigner: getChainId failed, falling back to static mapping', error: e);
      final n = name.toLowerCase();
      if (n.contains('bsc') || n.contains('binance')) return 56;
      if (n.contains('polygon')) return 137;
      if (n.contains('avalanche')) return 43114;
      if (n.contains('arbitrum')) return 42161;
      return 1;
    }
  }

  /// 🛡️ Re-broadcast an already-signed ERC20 transfer without re-signing.
  ///
  /// [signedData] must have been captured via the [onSigned] callback
  /// during a previous [sendErc20] call. The rawData is hex-encoded signed
  /// transaction bytes.
  Future<String> retryErc20(SignedTransactionData signedData) async {
    final rpc = WalletCoreConfig.evmRpcForBlockchain(signedData.blockchainName);
    final client = Web3Client(rpc, http.Client());
    try {
      final signedTx = HEX.decode(signedData.rawData);
      final txHash = await client.sendRawTransaction(Uint8List.fromList(signedTx));
      return txHash;
    } finally {
      client.dispose();
    }
  }
}
