import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

import '../core/evm_rpc_pool.dart';
import '../derivation/multi_chain_deriver.dart';

class EvmLocalSigner {
  Web3Client _clientFor(String blockchainName) {
    final url = EvmRpcPool.evmRpcForBlockchain(blockchainName);
    return Web3Client(url, http.Client());
  }

  Future<String> sendNative({
    required String mnemonic,
    required String blockchainName,
    required String recipient,
    required String amountEth,
  }) async {
    final derived = await const MultiChainDeriver().deriveAll(mnemonic);
    final match = derived.entries.firstWhere(
      (e) =>
          e.key.toLowerCase() == blockchainName.toLowerCase() ||
          (blockchainName.toLowerCase().contains('eth') &&
              e.key == 'Ethereum'),
      orElse: () => derived.entries.first,
    );
    final privHex = match.value.privateKeyHexOrWif;
    final credentials = EthPrivateKey.fromHex(
      privHex.startsWith('0x') ? privHex.substring(2) : privHex,
    );
    final from = credentials.address;
    final client = _clientFor(blockchainName);
    try {
      final to = EthereumAddress.fromHex(
        recipient.startsWith('0x') ? recipient : '0x$recipient',
      );
      final value = EtherAmount.fromUnitAndValue(
        EtherUnit.ether,
        _parseEtherToWei(amountEth),
      );
      final gasPrice = await client.getGasPrice();
      final nonce = await client.getTransactionCount(from);
      final tx = Transaction(
        to: to,
        gasPrice: gasPrice,
        maxGas: 21000,
        value: value,
        nonce: nonce,
      );
      final signed = await client.sendTransaction(
        credentials,
        tx,
        chainId: await _chainId(client, blockchainName),
      );
      return signed;
    } finally {
      client.dispose();
    }
  }

  BigInt _parseEtherToWei(String amount) {
    final parts = amount.split('.');
    final whole = BigInt.parse(parts[0]);
    var frac = BigInt.zero;
    if (parts.length > 1) {
      final f = parts[1].padRight(18, '0').substring(0, 18);
      frac = BigInt.parse(f);
    }
    return whole * BigInt.from(10).pow(18) + frac;
  }

  Future<int> _chainId(Web3Client client, String name) async {
    try {
      final id = await client.getChainId();
      return id.toInt();
    } catch (_) {
      final n = name.toLowerCase();
      if (n.contains('bsc') || n.contains('binance')) return 56;
      if (n.contains('polygon')) return 137;
      if (n.contains('avalanche')) return 43114;
      if (n.contains('arbitrum')) return 42161;
      return 1;
    }
  }

  Future<String> senderAddress(String mnemonic, String blockchainName) async {
    final derived = await const MultiChainDeriver().deriveAll(mnemonic);
    for (final e in derived.entries) {
      if (e.key.toLowerCase() == blockchainName.toLowerCase()) {
        return e.value.publicAddress;
      }
    }
    return derived['Ethereum']?.publicAddress ?? '';
  }
}
