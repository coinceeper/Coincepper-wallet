import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;
import 'package:wallet_core_bindings/wallet_core_bindings.dart';
import 'package:web3dart/web3dart.dart';

import '../../core/wallet_core_bridge.dart';
import '../../core/wallet_core_coin_map.dart';
import '../../core/wallet_core_config.dart';
import '../../tokens/token_metadata_service.dart';

/// ERC20/BEP20 transfer using private key from Wallet Core.
class EvmTokenSigner {
  Future<String?> sendErc20({
    required String mnemonic,
    required String blockchainName,
    required String senderAddress,
    required String contractAddress,
    required String recipient,
    required String amount,
    String tokenSymbol = '',
  }) async {
    final wallet = WalletCoreBridge.instance.openWallet(mnemonic);
    try {
      final coin = WalletCoreCoinMap.coinTypeForBlockchain(blockchainName) ??
          TWCoinType.Ethereum;
      final priv = wallet.getKeyForCoin(coin);
      final credentials = EthPrivateKey.fromHex(HEX.encode(priv.data));
      priv.delete();

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
        final decimals = await TokenMetadataService.instance.decimalsForToken(
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
        final hash = await client.sendTransaction(credentials, tx);
        return hash;
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
}
