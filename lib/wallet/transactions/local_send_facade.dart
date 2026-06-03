import 'package:uuid/uuid.dart';

import '../../services/api_models.dart';
import '../keys/secure_key_vault.dart';
import '../wallet_mode.dart';
import 'evm_local_signer.dart';
import 'signers/wallet_core_signer.dart';

class _PendingLocalSend {
  final String mnemonic;
  final String blockchainName;
  final String senderAddress;
  final String recipientAddress;
  final String amount;
  final String smartContractAddress;
  final String? transactionId;

  _PendingLocalSend({
    required this.mnemonic,
    required this.blockchainName,
    required this.senderAddress,
    required this.recipientAddress,
    required this.amount,
    required this.smartContractAddress,
    this.transactionId,
  });
}

/// On-device prepare/confirm for outbound transfers.
class LocalSendFacade {
  LocalSendFacade._();
  static final LocalSendFacade instance = LocalSendFacade._();

  final _pending = <String, _PendingLocalSend>{};
  final _wcSigner = const WalletCoreSigner();
  final _evmFallback = EvmLocalSigner();
  final _uuid = const Uuid();

  Future<bool> shouldUseLocalSend() async {
    return WalletModePreferences.isSelfCustodyEnabled();
  }

  Future<PrepareTransactionResponse> prepare({
    required String mnemonic,
    required String blockchainName,
    required String senderAddress,
    required String recipientAddress,
    required String amount,
    required String smartContractAddress,
  }) async {
    final txId = _uuid.v4();
    _pending[txId] = _PendingLocalSend(
      mnemonic: mnemonic,
      blockchainName: blockchainName,
      senderAddress: senderAddress,
      recipientAddress: recipientAddress,
      amount: amount,
      smartContractAddress: smartContractAddress,
      transactionId: txId,
    );

    return PrepareTransactionResponse(
      details: TransactionDetails(
        amount: amount,
        blockchain: blockchainName,
        estimatedFee: '0.0003',
        explorerUrl: '',
        recipient: recipientAddress,
        sender: senderAddress,
        senderBalanceAfter: '0',
        senderBalanceBefore: '0',
      ),
      expiresAt: DateTime.now().add(const Duration(minutes: 15)).toIso8601String(),
      message: 'Prepared locally',
      success: true,
      transactionId: txId,
    );
  }

  Future<String?> confirm({
    required String mnemonic,
    required String blockchainName,
    required String recipientAddress,
    required String amount,
    required String smartContractAddress,
    String? transactionId,
  }) async {
    final ok = await SecureKeyVault.instance.authenticateForSigning();
    if (!ok) return null;

    _PendingLocalSend? pending;
    if (transactionId != null) {
      pending = _pending.remove(transactionId);
    }
    final chain = pending?.blockchainName ?? blockchainName;
    final recipient = pending?.recipientAddress ?? recipientAddress;
    final amt = pending?.amount ?? amount;
    final phrase = pending?.mnemonic ?? mnemonic;
    final contract = pending?.smartContractAddress ?? smartContractAddress;
    final sender = pending?.senderAddress ?? '';

    try {
      return await _wcSigner.send(
        mnemonic: phrase,
        blockchainName: chain,
        senderAddress: sender,
        recipient: recipient,
        amount: amt,
        smartContractAddress: contract,
      );
    } catch (_) {
      final n = chain.toLowerCase();
      if (contract.isEmpty && _isEvm(n)) {
        return _evmFallback.sendNative(
          mnemonic: phrase,
          blockchainName: chain,
          recipient: recipient,
          amountEth: amt,
        );
      }
      rethrow;
    }
  }

  bool _isEvm(String chain) {
    return chain.contains('eth') ||
        chain.contains('bsc') ||
        chain.contains('binance') ||
        chain.contains('polygon') ||
        chain.contains('avalanche') ||
        chain.contains('arbitrum');
  }
}
