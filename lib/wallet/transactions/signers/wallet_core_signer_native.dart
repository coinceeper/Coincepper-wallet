import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;
import 'package:wallet_core_bindings/wallet_core_bindings.dart';
import 'package:wallet_core_bindings/proto/Bitcoin.pb.dart' as bitcoin;
import 'package:wallet_core_bindings/proto/Ethereum.pb.dart' as ethereum;
import 'package:wallet_core_bindings/proto/Polkadot.pb.dart' as polkadot;
import 'package:wallet_core_bindings/proto/Ripple.pb.dart' as ripple;
import 'package:wallet_core_bindings/proto/Solana.pb.dart' as solana;
import 'package:wallet_core_bindings/proto/Tron.pb.dart' as tron;

import '../../core/wallet_core_bridge.dart';
import '../../core/wallet_core_coin_map.dart';
import '../../core/wallet_core_config.dart';
import '../../core/evm_rpc_pool.dart';
import '../../../services/build_secrets.dart';
import '../../../services/sensitive_data.dart';
import '../../../utils/secure_log.dart';
import '../../tokens/token_metadata_service.dart';
import '../../utils/scale_codec.dart';
import '../fees/evm_fee_estimator.dart';
import '../signed_transaction_data.dart';
import 'evm_token_signer.dart';
import '../../../di/service_locator.dart';

/// Signs and broadcasts via Trust Wallet Core (+ public RPC/indexers).
///
/// ## 🛡️ Double-Spend Prevention
///
/// Broadcasting an already-signed raw transaction is **idempotent**: the same
/// signed bytes submitted N times will only produce one on-chain effect.
/// Therefore retry happens on the **broadcast** step only — NEVER on the
/// **sign** step. This guarantees that if the first broadcast succeeded but
/// the HTTP response was lost, a retry broadcasts the exact same signed
/// transaction, eliminating double-spend risk.
class WalletCoreSigner {
  WalletCoreSigner();

  final _evmFees = const EvmFeeEstimator();

  Future<String?> send({
    required String mnemonic,
    required String blockchainName,
    required String senderAddress,
    required String recipient,
    required String amount,
    required String smartContractAddress,
    void Function(SignedTransactionData)? onSigned,
  }) async {
    if (smartContractAddress.isNotEmpty) {
      final chain = blockchainName.toLowerCase();
      if (chain.contains('tron') || chain == 'trx') {
        return _sendTrc20(
          mnemonic: mnemonic,
          blockchainName: blockchainName,
          contractAddress: smartContractAddress,
          recipient: recipient,
          amount: amount,
          onSigned: onSigned,
        );
      }
      return EvmTokenSigner().sendErc20(
        mnemonic: mnemonic,
        blockchainName: blockchainName,
        senderAddress: senderAddress,
        contractAddress: smartContractAddress,
        recipient: recipient,
        amount: amount,
        onSigned: onSigned,
      );
    }

    final chain = blockchainName.toLowerCase();
    if (_isEvm(chain)) {
      return _sendEvmNative(
        mnemonic: mnemonic,
        blockchainName: blockchainName,
        recipient: recipient,
        amount: amount,
        onSigned: onSigned,
      );
    }
    if (chain.contains('bitcoin') || chain == 'btc') {
      return _sendBitcoin(
        mnemonic: mnemonic,
        senderAddress: senderAddress,
        recipient: recipient,
        amount: amount,
        onSigned: onSigned,
      );
    }
    if (chain.contains('tron') || chain == 'trx') {
      return _sendTron(
        mnemonic: mnemonic,
        recipient: recipient,
        amount: amount,
        onSigned: onSigned,
      );
    }
    if (chain.contains('solana') || chain == 'sol') {
      return _sendSolana(
        mnemonic: mnemonic,
        recipient: recipient,
        amount: amount,
        onSigned: onSigned,
      );
    }
    if (chain.contains('xrp') || chain == 'ripple') {
      return _sendXrp(
        mnemonic: mnemonic,
        recipient: recipient,
        amount: amount,
        onSigned: onSigned,
      );
    }
    if (chain.contains('polkadot') || chain == 'dot') {
      return _sendPolkadot(
        mnemonic: mnemonic,
        recipient: recipient,
        amount: amount,
        onSigned: onSigned,
      );
    }
    throw UnsupportedError('Local send not yet implemented for $blockchainName');
  }

  bool _isEvm(String chain) {
    return chain.contains('eth') ||
        chain.contains('bsc') ||
        chain.contains('binance') ||
        chain.contains('polygon') ||
        chain.contains('avalanche') ||
        chain.contains('arbitrum');
  }

  /// Maximum attempts for broadcasting a signed transaction.
  /// Broadcasting the same raw transaction multiple times is idempotent,
  /// so retry here is safe and cannot cause double-spend.
  static const _maxBroadcastRetries = 3;

  /// Idempotent broadcast: retries the broadcast function with the SAME
  /// signed raw transaction. Since the signed bytes never change between
  /// retries, this cannot produce a duplicate on-chain transaction.
  Future<String> _broadcastWithRetry(
    Future<String> Function() broadcastFn,
    String chainLabel,
  ) async {
    for (var i = 0; i < _maxBroadcastRetries; i++) {
      try {
        return await broadcastFn();
      } catch (e) {
        if (i == _maxBroadcastRetries - 1) {
          rethrow;
        }
        SecureLog.i('$chainLabel broadcast retry ${i + 1}/$_maxBroadcastRetries '
            '(same signed tx — idempotent, no double-spend risk)');
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    throw StateError('$chainLabel broadcast failed after $_maxBroadcastRetries attempts');
  }

  Future<String> _sendEvmNative({
    required String mnemonic,
    required String blockchainName,
    required String recipient,
    required String amount,
    void Function(SignedTransactionData)? onSigned,
  }) async {
    final wallet = ServiceLocator.get<WalletCoreBridge>().openWallet(mnemonic);
    try {
      final coin = WalletCoreCoinMap.coinTypeForBlockchain(blockchainName) ??
          TWCoinType.Ethereum;
      final priv = wallet.getKeyForCoin(coin);
      final privData = priv.data;
      final chainId = WalletCoreConfig.evmChainId(blockchainName);
      final wei = _etherToWeiBytes(amount);
      final input = ethereum.SigningInput(
        chainId: _uint256Bytes(chainId),
        gasPrice: _uint256Bytes(await _evmFees.gasPriceWei(blockchainName)),
        gasLimit: _uint256Bytes(21000),
        toAddress: recipient.startsWith('0x') ? recipient : '0x$recipient',
        privateKey: privData,
        transaction: ethereum.Transaction(
          transfer: ethereum.Transaction_Transfer(amount: wei),
        ),
      );
      final output = input.sign(coin);
      final hexTx = HEX.encode(output.encoded);
      priv.delete();
      privData.secureWipe();
      // 🛡️ Store signed tx for idempotent retry before broadcasting
      onSigned?.call(SignedTransactionData(
        rawData: hexTx,
        chainLabel: 'EVM',
        blockchainName: blockchainName,
      ));
      // 🛡️ Idempotent broadcast: same hexTx on each retry → no double-spend
      return _broadcastWithRetry(
        () => _broadcastEvmRaw(hexTx, blockchainName),
        'EVM',
      );
    } finally {
      wallet.delete();
    }
  }

  Future<String> _sendBitcoin({
    required String mnemonic,
    required String senderAddress,
    required String recipient,
    required String amount,
    void Function(SignedTransactionData)? onSigned,
  }) async {
    final wallet = ServiceLocator.get<WalletCoreBridge>().openWallet(mnemonic);
    try {
      const coin = TWCoinType.Bitcoin;
      final priv = wallet.getKeyDerivation(coin, TWDerivation.BitcoinSegwit);
      final privData = priv.data;
      final utxos = await _fetchUtxos(senderAddress);
      if (utxos.isEmpty) {
        priv.delete();
        privData.secureWipe();
        throw StateError('No UTXOs available for Bitcoin send');
      }
      final satoshi = BigInt.from((double.parse(amount) * 1e8).round());
      final input = bitcoin.SigningInput(
        hashType: TWBitcoinScript.hashTypeForCoin(coin),
        amount: Int64(satoshi.toInt()),
        byteFee: Int64(10),
        toAddress: recipient,
        changeAddress: senderAddress,
        privateKey: [privData],
        utxo: utxos,
        coinType: coin.value,
        useMaxAmount: false,
      );
      final output = input.sign();
      final raw = output.encoded;
      priv.delete();
      privData.secureWipe();
      if (raw.isEmpty) {
        throw StateError(output.errorMessage.isNotEmpty
            ? output.errorMessage
            : 'Bitcoin signing failed');
      }
      final encodedTx = HEX.encode(raw);
      // 🛡️ Store signed tx for idempotent retry before broadcasting
      onSigned?.call(SignedTransactionData(
        rawData: encodedTx,
        chainLabel: 'BTC',
        blockchainName: 'bitcoin',
      ));
      // 🛡️ Idempotent broadcast: same raw tx on each retry → no double-spend
      return _broadcastWithRetry(
        () => _broadcastBtc(encodedTx),
        'BTC',
      );
    } finally {
      wallet.delete();
    }
  }

  Future<String> _sendTron({
    required String mnemonic,
    required String recipient,
    required String amount,
    void Function(SignedTransactionData)? onSigned,
  }) async {
    final wallet = ServiceLocator.get<WalletCoreBridge>().openWallet(mnemonic);
    try {
      const coin = TWCoinType.Tron;
      final priv = wallet.getKeyForCoin(coin);
      final privData = priv.data;
      final from = wallet.getAddressForCoin(coin);
      final sun = Int64((double.parse(amount) * 1e6).round());
      final tx = tron.Transaction(
        transfer: tron.TransferContract(
          ownerAddress: from,
          toAddress: recipient,
          amount: sun,
        ),
      );
      final input = tron.SigningInput(
        transaction: tx,
        privateKey: privData,
      );
      final output = input.sign();
      priv.delete();
      privData.secureWipe();
      final jsonTx = output.json;
      if (jsonTx.isEmpty) {
        throw StateError('TRON signing failed');
      }
      // 🛡️ Store signed tx for idempotent retry before broadcasting
      onSigned?.call(SignedTransactionData(
        rawData: jsonTx,
        chainLabel: 'TRON',
        blockchainName: 'tron',
      ));
      // 🛡️ Idempotent broadcast: same jsonTx on each retry → no double-spend
      return _broadcastWithRetry(
        () => _broadcastTron(jsonTx),
        'TRON',
      );
    } finally {
      wallet.delete();
    }
  }

  Future<Uint8List> _btcUtxoScript(String txid, int vout) async {
    final uri = Uri.parse('https://blockstream.info/api/tx/$txid');
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return Uint8List(0);
    final tx = jsonDecode(res.body) as Map<String, dynamic>;
    final outputs = tx['vout'] as List<dynamic>? ?? [];
    if (vout < 0 || vout >= outputs.length) return Uint8List(0);
    final item = outputs[vout];
    if (item is! Map) return Uint8List(0);
    final hex = item['scriptpubkey']?.toString() ?? '';
    if (hex.isEmpty) return Uint8List(0);
    return Uint8List.fromList(HEX.decode(hex));
  }

  Future<List<bitcoin.UnspentTransaction>> _fetchUtxos(String address) async {
    final uri = Uri.parse('https://blockstream.info/api/address/$address/utxo');
    final res = await http.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) return [];
    final list = jsonDecode(res.body) as List<dynamic>;
    final out = <bitcoin.UnspentTransaction>[];
    for (final u in list) {
      if (u is! Map) continue;
      final txid = u['txid']?.toString() ?? '';
      final vout = u['vout'] as int? ?? 0;
      final value = u['value'] as int? ?? 0;
      if (txid.isEmpty || value <= 0) continue;
      final script = await _btcUtxoScript(txid, vout);
      out.add(bitcoin.UnspentTransaction(
        outPoint: bitcoin.OutPoint(
          hash: _hexToBytesReversed(txid),
          index: vout,
          sequence: 0xffffffff,
        ),
        amount: Int64(value),
        script: script,
      ));
    }
    return out;
  }

  Uint8List _hexToBytesReversed(String hex) {
    final bytes = HEX.decode(hex);
    return Uint8List.fromList(bytes.reversed.toList());
  }

  Uint8List _etherToWeiBytes(String amount) {
    final parts = amount.split('.');
    final whole = BigInt.parse(parts[0]);
    var frac = BigInt.zero;
    if (parts.length > 1) {
      final f = parts[1].padRight(18, '0').substring(0, 18);
      frac = BigInt.parse(f);
    }
    final wei = whole * BigInt.from(10).pow(18) + frac;
    return _uint256BytesFromBigInt(wei);
  }

  Uint8List _uint256Bytes(int value) => _uint256BytesFromBigInt(BigInt.from(value));

  Uint8List _uint256BytesFromBigInt(BigInt value) {
    final bytes = Uint8List(32);
    var v = value;
    for (var i = 31; i >= 0; i--) {
      bytes[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return bytes;
  }

  Future<String> _broadcastEvmRaw(String hexTx, String blockchainName) async {
    final result = await EvmRpcPool.tryPost(blockchainName, {
      'jsonrpc': '2.0',
      'method': 'eth_sendRawTransaction',
      'params': ['0x$hexTx'],
      'id': 1,
    }, timeout: const Duration(seconds: 30));
    return result['result']?.toString() ?? '';
  }

  Future<String> _broadcastBtc(String hexTx) async {
    // Try BlockCypher (with API keys), then Chainstack, then BlockPI, then Blockstream

    // 1. BlockCypher (6 keys, 18 req/sec total)
    final btcKeys = BuildSecrets.blockcypherApiKeys;
    for (final key in btcKeys) {
      try {
        final res = await http
            .post(
              Uri.parse('https://api.blockcypher.com/v1/btc/main/txs/push?token=$key'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'tx': hexTx}),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200 || res.statusCode == 201) {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          final txid = map['tx']['hash']?.toString() ?? map['tx']?.toString() ?? '';
          if (txid.isNotEmpty) return txid;
        }
      } catch (e) {
        SecureLog.w('WalletCoreSigner: BTC broadcast attempt failed, trying next provider', error: e);
        continue;
      }
    }

    // 2. Chainstack BTC
    if (BuildSecrets.chainstackBtcToken.isNotEmpty) {
      try {
        final res = await http
            .post(
              Uri.parse(
                'https://bitcoin-mainnet.core.chainstack.com/${BuildSecrets.chainstackBtcToken}',
              ),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'jsonrpc': '2.0',
                'method': 'sendrawtransaction',
                'params': [hexTx],
                'id': 1,
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          if (map['error'] == null) {
            return map['result']?.toString() ?? hexTx;
          }
        }
      } catch (e) {
        SecureLog.d('NowNodes BTC broadcast failed', error: e);
      }
    }

    // 3. BlockPI BTC
    if (BuildSecrets.blockpiBtcRpc.isNotEmpty) {
      try {
        final res = await http
            .post(
              Uri.parse(BuildSecrets.blockpiBtcRpc),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'jsonrpc': '2.0',
                'method': 'sendrawtransaction',
                'params': [hexTx],
                'id': 1,
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          if (map['error'] == null) {
            return map['result']?.toString() ?? hexTx;
          }
        }
      } catch (e) {
        SecureLog.d('BlockPI BTC broadcast failed', error: e);
      }
    }

    // 4. Blockstream (last resort)
    final res = await http
        .post(
          Uri.parse('https://blockstream.info/api/tx'),
          headers: {'Content-Type': 'text/plain'},
          body: hexTx,
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode >= 400) {
      throw StateError(res.body);
    }
    return res.body.trim();
  }

  Future<String> _sendTrc20({
    required String mnemonic,
    required String blockchainName,
    required String contractAddress,
    required String recipient,
    required String amount,
    void Function(SignedTransactionData)? onSigned,
  }) async {
    final tokenDecimals = await ServiceLocator.get<TokenMetadataService>().decimalsForToken(
      blockchainName: blockchainName,
      contractAddress: contractAddress,
      symbol: '',
    );
    final wallet = ServiceLocator.get<WalletCoreBridge>().openWallet(mnemonic);
    try {
      const coin = TWCoinType.Tron;
      final priv = wallet.getKeyForCoin(coin);
      final privData = priv.data;
      final from = wallet.getAddressForCoin(coin);
      final rawAmount = _tokenAmountBytes(amount, tokenDecimals);
      final tx = tron.Transaction(
        transferTrc20Contract: tron.TransferTRC20Contract(
          contractAddress: contractAddress,
          ownerAddress: from,
          toAddress: recipient,
          amount: rawAmount,
        ),
      );
      final input = tron.SigningInput(
        transaction: tx,
        privateKey: privData,
      );
      final output = input.sign();
      priv.delete();
      privData.secureWipe();
      final jsonTx = output.json;
      if (jsonTx.isEmpty) {
        throw StateError('TRC20 signing failed');
      }
      // 🛡️ Store signed tx for idempotent retry before broadcasting
      onSigned?.call(SignedTransactionData(
        rawData: jsonTx,
        chainLabel: 'TRC20',
        blockchainName: 'tron',
      ));
      // 🛡️ Idempotent broadcast: same jsonTx on each retry → no double-spend
      return _broadcastWithRetry(
        () => _broadcastTron(jsonTx),
        'TRC20',
      );
    } finally {
      wallet.delete();
    }
  }

  Future<String> _sendSolana({
    required String mnemonic,
    required String recipient,
    required String amount,
    void Function(SignedTransactionData)? onSigned,
  }) async {
    final wallet = ServiceLocator.get<WalletCoreBridge>().openWallet(mnemonic);
    try {
      const coin = TWCoinType.Solana;
      final priv = wallet.getKeyForCoin(coin);
      final privData = priv.data;
      final sender = wallet.getAddressForCoin(coin);
      final blockhash = await _solanaRecentBlockhash();
      final lamports = Int64((double.parse(amount) * 1e9).round());
      final input = solana.SigningInput(
        privateKey: privData,
        recentBlockhash: blockhash,
        sender: sender,
        transferTransaction: solana.Transfer(
          recipient: recipient,
          value: lamports,
        ),
      );
      final output = input.sign(coin);
      priv.delete();
      privData.secureWipe();
      if (output.encoded.isEmpty) {
        throw StateError(output.errorMessage.isNotEmpty
            ? output.errorMessage
            : 'Solana signing failed');
      }
      final encodedTx = output.encoded;
      // 🛡️ Store signed tx for idempotent retry before broadcasting
      onSigned?.call(SignedTransactionData(
        rawData: encodedTx,
        chainLabel: 'SOL',
        blockchainName: 'solana',
      ));
      // 🛡️ Idempotent broadcast: same encoded tx on each retry → no double-spend
      return _broadcastWithRetry(
        () => _broadcastSolana(encodedTx),
        'Solana',
      );
    } finally {
      wallet.delete();
    }
  }

  Future<String> _sendXrp({
    required String mnemonic,
    required String recipient,
    required String amount,
    void Function(SignedTransactionData)? onSigned,
  }) async {
    final wallet = ServiceLocator.get<WalletCoreBridge>().openWallet(mnemonic);
    try {
      const coin = TWCoinType.XRP;
      final priv = wallet.getKeyForCoin(coin);
      final privData = priv.data;
      final account = wallet.getAddressForCoin(coin);
      final meta = await _xrpAccountMeta(account);
      final drops = Int64((double.parse(amount) * 1e6).round());
      final input = ripple.SigningInput(
        fee: Int64(12),
        sequence: meta.sequence,
        lastLedgerSequence: meta.lastLedgerSequence,
        account: account,
        privateKey: privData,
        opPayment: ripple.OperationPayment(
          amount: drops,
          destination: recipient,
        ),
      );
      final output = input.sign(coin);
      priv.delete();
      privData.secureWipe();
      if (output.encoded.isEmpty) {
        throw StateError(output.errorMessage.isNotEmpty
            ? output.errorMessage
            : 'XRP signing failed');
      }
      final txBlob = HEX.encode(output.encoded);
      // 🛡️ Store signed tx for idempotent retry before broadcasting
      onSigned?.call(SignedTransactionData(
        rawData: txBlob,
        chainLabel: 'XRP',
        blockchainName: 'xrp',
      ));
      // 🛡️ Idempotent broadcast: same txBlob on each retry → no double-spend
      return _broadcastWithRetry(
        () => _broadcastXrp(txBlob),
        'XRP',
      );
    } finally {
      wallet.delete();
    }
  }

  static final _polkadotGenesisHash = HEX.decode(
    '91b171bb158e2d3848fa23a9f1c25182fb8e20313b2c1eb49219da7a70ce90c3',
  );

  Future<String> _sendPolkadot({
    required String mnemonic,
    required String recipient,
    required String amount,
    void Function(SignedTransactionData)? onSigned,
  }) async {
    final wallet = ServiceLocator.get<WalletCoreBridge>().openWallet(mnemonic);
    try {
      const coin = TWCoinType.Polkadot;
      final priv = wallet.getKeyDerivation(coin, TWDerivation.Default);
      final privData = priv.data;
      final from = wallet.getAddressForCoin(coin);
      final runtime = await _substrateRpc('chain_getRuntimeVersion', [], endpoint: 'https://rpc.polkadot.io');
      final headHash = await _substrateRpc('chain_getFinalizedHead', [], endpoint: 'https://rpc.polkadot.io');
      final header = await _substrateRpc('chain_getHeader', [headHash], endpoint: 'https://rpc.polkadot.io');
      final blockNumber = _parseHexInt(header['number'] as String? ?? '0x0');
      final blockHashHex = (header['parentHash'] as String?) ?? headHash;
      final blockHash = HEX.decode(blockHashHex.replaceFirst('0x', ''));
      final nonce = await _substrateRpc(
        'system_accountNextIndex',
        [from],
        endpoint: 'https://rpc.polkadot.io',
      );
      final planck = BigInt.from((double.parse(amount) * 1e10).round());
      final input = polkadot.SigningInput(
        genesisHash: _polkadotGenesisHash,
        blockHash: blockHash,
        nonce: Int64(_jsonInt(nonce)),
        specVersion: _parseHexInt(runtime['specVersion'] as String? ?? '0x0'),
        transactionVersion:
            _parseHexInt(runtime['transactionVersion'] as String? ?? '0x0'),
        era: polkadot.Era(
          blockNumber: Int64(blockNumber),
          period: Int64(64),
        ),
        privateKey: privData,
        network: 0,
        multiAddress: true,
        balanceCall: polkadot.Balance(
          transfer: polkadot.Balance_Transfer(
            toAddress: recipient,
            value: scaleCompactU128(planck),
          ),
        ),
      );
      final output = input.sign(coin);
      priv.delete();
      privData.secureWipe();
      if (output.encoded.isEmpty) {
        throw StateError(output.errorMessage.isNotEmpty
            ? output.errorMessage
            : 'Polkadot signing failed');
      }
      final extrinsicHex = HEX.encode(output.encoded);
      // 🛡️ Store signed tx for idempotent retry before broadcasting
      onSigned?.call(SignedTransactionData(
        rawData: extrinsicHex,
        chainLabel: 'DOT',
        blockchainName: 'polkadot',
      ));
      // 🛡️ Idempotent broadcast: same extrinsic on each retry → no double-spend
      return _broadcastWithRetry(
        () => _broadcastPolkadot(extrinsicHex),
        'Polkadot',
      );
    } finally {
      wallet.delete();
    }
  }

  Future<String> _solanaRecentBlockhash() async {
    final rpc = _solanaRpcUrl();
    final res = await http
        .post(
          Uri.parse(rpc),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'getLatestBlockhash',
            'params': [{'commitment': 'finalized'}],
          }),
        )
        .timeout(const Duration(seconds: 25));
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final value = map['result']?['value'] as Map<String, dynamic>?;
    final hash = value?['blockhash']?.toString() ?? '';
    if (hash.isEmpty) throw StateError('Solana blockhash unavailable');
    return hash;
  }

  String _solanaRpcUrl() {
    if (BuildSecrets.solanaRpcUrl.isNotEmpty) {
      return BuildSecrets.solanaRpcUrl;
    }
    return 'https://api.mainnet-beta.solana.com';
  }

  Future<_XrpAccountMeta> _xrpAccountMeta(String account) async {
    final rpc = _xrpRpcUrl();
    final res = await http
        .post(
          Uri.parse(rpc),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'method': 'account_info',
            'params': [
              {
                'account': account,
                'ledger_index': 'current',
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 25));
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final result = map['result'] as Map<String, dynamic>?;
    final info = result?['account_data'] as Map<String, dynamic>?;
    final ledger = result?['ledger_current_index'] as int? ?? 0;
    final seq = info?['Sequence'] as int? ?? 0;
    return _XrpAccountMeta(
      sequence: seq,
      lastLedgerSequence: ledger + 20,
    );
  }

  String _xrpRpcUrl() {
    if (BuildSecrets.drpcApiKey.isNotEmpty) {
      return 'https://lb.drpc.live/xrp/${BuildSecrets.drpcApiKey}';
    }
    return 'https://s1.ripple.com:51234/';
  }

  String _polkadotRpcUrl() {
    if (BuildSecrets.drpcApiKey.isNotEmpty) {
      return 'https://lb.drpc.live/polkadot/${BuildSecrets.drpcApiKey}';
    }
    return 'https://rpc.polkadot.io';
  }

  Future<dynamic> _substrateRpc(
    String method,
    List<dynamic> params, {
    String? endpoint,
  }) async {
    final rpc = endpoint ?? _polkadotRpcUrl();
    final res = await http
        .post(
          Uri.parse(rpc),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': method,
            'params': params,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    if (map['error'] != null) {
      throw StateError(map['error'].toString());
    }
    return map['result'];
  }

  int _parseHexInt(String hex) {
    final h = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (h.isEmpty) return 0;
    return int.parse(h, radix: 16);
  }

  int _jsonInt(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      if (value.startsWith('0x')) return _parseHexInt(value);
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  Uint8List _tokenAmountBytes(String amount, int decimals) {
    final parts = amount.split('.');
    final whole = BigInt.parse(parts[0]);
    var frac = BigInt.zero;
    if (parts.length > 1) {
      final f = parts[1].padRight(decimals, '0').substring(0, decimals);
      frac = BigInt.parse(f);
    }
    final value = whole * BigInt.from(10).pow(decimals) + frac;
    return _uint256BytesFromBigInt(value);
  }

  Future<String> _broadcastSolana(String encoded) async {
    final rpc = _solanaRpcUrl();
    final res = await http
        .post(
          Uri.parse(rpc),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'sendTransaction',
            'params': [
              encoded,
              {'encoding': 'base58', 'preflightCommitment': 'finalized'},
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    if (map['error'] != null) {
      throw StateError(map['error'].toString());
    }
    return map['result']?.toString() ?? '';
  }

  Future<String> _broadcastXrp(String txBlobHex) async {
    final rpc = _xrpRpcUrl();
    final res = await http
        .post(
          Uri.parse(rpc),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'method': 'submit',
            'params': [
              {'tx_blob': txBlobHex},
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final result = map['result'] as Map<String, dynamic>?;
    if (result?['engine_result'] != 'tesSUCCESS') {
      throw StateError(result?.toString() ?? map.toString());
    }
    return result?['tx_json']?['hash']?.toString() ?? txBlobHex;
  }

  Future<String> _broadcastPolkadot(String extrinsicHex) async {
    // Try dRPC first, fallback to rpc.polkadot.io
    for (final rpc in [_polkadotRpcUrl(), 'https://rpc.polkadot.io']) {
      try {
        final res = await http
            .post(
              Uri.parse(rpc),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'method': 'author_submitExtrinsic',
                'params': ['0x$extrinsicHex'],
              }),
            )
            .timeout(const Duration(seconds: 30));
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        if (map['error'] != null) continue;
        return map['result']?.toString() ?? extrinsicHex;
      } catch (e) {
        SecureLog.w('WalletCoreSigner: Polkadot broadcast attempt failed, trying next RPC', error: e);
        continue;
      }
    }
    throw StateError('All Polkadot RPCs failed');
  }

  Future<String> _broadcastTron(String jsonTx) async {
    final res = await http
        .post(
          Uri.parse('https://api.trongrid.io/wallet/broadcasttransaction'),
          headers: _trongridHeaders(),
          body: jsonTx,
        )
        .timeout(const Duration(seconds: 30));
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    if (map['result'] != true && map['code'] != null) {
      throw StateError(map.toString());
    }
    return map['txid']?.toString() ?? map['txID']?.toString() ?? '';
  }

  Map<String, String> _trongridHeaders() {
    final keys = BuildSecrets.trongridApiKeys;
    final key = keys.isNotEmpty ? keys.first : '';
    return key.isNotEmpty
        ? {'Content-Type': 'application/json', 'TRON-PRO-API-KEY': key}
        : {'Content-Type': 'application/json'};
  }

  /// 🛡️ Re-broadcast an already-signed transaction without re-signing.
  ///
  /// This is the core of the "sign once, broadcast many" pattern.
  /// [signedData] must have been captured via the [onSigned] callback
  /// during a previous [send] call.
  Future<String> retryBroadcast(SignedTransactionData signedData) async {
    switch (signedData.chainLabel) {
      case 'EVM':
        return _broadcastEvmRaw(signedData.rawData, signedData.blockchainName);
      case 'BTC':
        return _broadcastBtc(signedData.rawData);
      case 'TRON':
      case 'TRC20':
        return _broadcastTron(signedData.rawData);
      case 'SOL':
        return _broadcastSolana(signedData.rawData);
      case 'XRP':
        return _broadcastXrp(signedData.rawData);
      case 'DOT':
        return _broadcastPolkadot(signedData.rawData);
      default:
        throw UnsupportedError(
          'No broadcast implementation for chain label: ${signedData.chainLabel}',
        );
    }
  }
}

class _XrpAccountMeta {
  final int sequence;
  final int lastLedgerSequence;

  const _XrpAccountMeta({
    required this.sequence,
    required this.lastLedgerSequence,
  });
}
