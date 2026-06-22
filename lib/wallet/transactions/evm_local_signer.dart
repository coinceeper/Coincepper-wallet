import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:wallet_core_bindings/wallet_core_bindings.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;

import '../core/wallet_core_bridge.dart';
import '../core/wallet_core_coin_map.dart';
import '../core/wallet_core_config.dart';
import '../../di/service_locator.dart';
import '../../utils/secure_log.dart';

/// Sign and broadcast EVM native token transfers using web3dart.
///
/// This is a fallback path when WalletCore signing fails (e.g. library
/// initialization issue). It reconstructs the private key from the mnemonic
/// via [WalletCoreBridge] and signs with web3dart's [EthPrivateKey].
class EvmLocalSigner {
  /// Send native coin (ETH/BNB/MATIC/etc.) directly.
  Future<String?> sendNative({
    required String mnemonic,
    required String blockchainName,
    required String recipient,
    required String amountEth,
  }) async {
    try {
      final wallet = ServiceLocator.get<WalletCoreBridge>().openWallet(mnemonic);
      try {
        final coin = WalletCoreCoinMap.coinTypeForBlockchain(blockchainName) ??
            TWCoinType.Ethereum;
        final priv = wallet.getKeyForCoin(coin);
        final privData = priv.data;
        final key = EthPrivateKey.fromHex(HEX.encode(privData));
        priv.delete();

        final chainId = WalletCoreConfig.evmChainId(blockchainName);
        final rpcUrl = WalletCoreConfig.evmRpcForBlockchain(blockchainName);
        final client = Web3Client(rpcUrl, http.Client());

        try {
          final sender = key.address;
          final amountWei = EtherAmount.fromBigInt(EtherUnit.ether, _parseAmount(amountEth));
          final tx = Transaction(
            from: sender,
            to: EthereumAddress.fromHex(recipient),
            value: amountWei,
            maxGas: 21000,
          );
          final signedTx = await client.signTransaction(key, tx, chainId: chainId);
          final hash = await client.sendRawTransaction(Uint8List.fromList(signedTx));
          return hash;
        } finally {
          client.dispose();
        }
      } finally {
        wallet.delete();
      }
    } catch (e) {
      SecureLog.e('EvmLocalSigner: sendNative failed', error: e);
      return null;
    }
  }

  BigInt _parseAmount(String amount) {
    final parts = amount.split('.');
    final whole = BigInt.parse(parts[0]);
    BigInt frac = BigInt.zero;
    if (parts.length > 1) {
      final f = parts[1].padRight(18, '0').substring(0, 18);
      frac = BigInt.parse(f);
    }
    return whole * BigInt.from(10).pow(18) + frac;
  }
}
