import 'package:uuid/uuid.dart';

import '../../di/service_locator.dart';
import '../../services/api_models.dart';
import '../../services/sensitive_data.dart';
import '../../services/secure_storage.dart';
import '../keys/secure_key_vault.dart';
import '../wallet_mode.dart';
import 'evm_local_signer.dart';
import 'signed_transaction_data.dart';
import 'signers/evm_token_signer.dart';
import 'signers/wallet_core_signer.dart';
import '../../utils/secure_log.dart';

/// اطلاعات pending یک تراکنش محلی.
///
/// ⚠️ توجه امنیتی: این کلاس NEVER منیمونیک را ذخیره می‌کند.
/// SignedTransactionData شامل تراکنش امضا شده است که یکبارمصرف است
/// (nonce-based) و نمی‌تواند دوباره استفاده شود.
class _PendingLocalSend {
  /// نام کیف پول (برای بازیابی منیمونیک در confirm)
  final String walletName;
  /// شناسه کاربر (برای بازیابی منیمونیک در confirm)
  final String userId;
  final String blockchainName;
  final String senderAddress;
  final String recipientAddress;
  final String amount;
  final String smartContractAddress;
  final String? transactionId;

  /// 🛡️ Signed transaction data captured after the first sign attempt.
  /// Stored for idempotent broadcast retry — avoids re-signing.
  SignedTransactionData? signedTransactionData;

  /// Whether the transaction has been signed at least once.
  bool get isSigned => signedTransactionData != null;

  _PendingLocalSend({
    required this.walletName,
    required this.userId,
    required this.blockchainName,
    required this.senderAddress,
    required this.recipientAddress,
    required this.amount,
    required this.smartContractAddress,
    this.transactionId,
  });
}

/// On-device prepare/confirm for outbound transfers.
///
/// ## امنیت حافظه
///
/// برخلاف طراحی قبلی که منیمونیک را در فیلد `_PendingLocalSend.mnemonic`
/// تا ۱۵ دقیقه نگه می‌داشت، این پیاده‌سازی جدید:
///
/// 1. منیمونیک را در [prepare] ذخیره نمی‌کند
/// 2. در [confirm] منیمونیک را از SecureStorage می‌خواند
/// 3. از [MnemonicScope] برای محدود کردن طول عمر منیمونیک در حافظه استفاده می‌کند
/// 4. پس از امضا، reference منیمونیک پاک می‌شود
///
/// ## 🛡️ "Sign Once, Broadcast Many" (Double-Spend Prevention)
///
/// برخلاف طراحی قبلی که در retry دوباره امضا می‌کرد، این نسخه:
/// 1. در اولین [confirm] تراکنش را امضا کرده و SignedTransactionData را ذخیره می‌کند
/// 2. [retryBroadcast] از همان داده‌های امضا شده استفاده می‌کند و دوباره امضا نمی‌کند
/// 3. Broadcast یک تراکنش امضا شده idempotent است و double-spend ایجاد نمی‌کند
class LocalSendFacade {
  LocalSendFacade._();
  /// DI constructor. Use [instance] for singleton access.
  LocalSendFacade();
  static LocalSendFacade get instance => ServiceLocator.get<LocalSendFacade>();

  final _pending = <String, _PendingLocalSend>{};
  final _wcSigner = WalletCoreSigner();
  final _evmFallback = EvmLocalSigner();
  final _evmTokenSigner = EvmTokenSigner();
  final _uuid = const Uuid();

  Future<bool> shouldUseLocalSend() async {
    return WalletModePreferences.isSelfCustodyEnabled();
  }

  /// مرحله آماده‌سازی تراکنش.
  ///
  /// این متد منیمونیک را ذخیره نمی‌کند. فقط ابرداده تراکنش را برای
  /// مرحله تایید (confirm) نگه می‌دارد.
  Future<PrepareTransactionResponse> prepare({
    required String walletName,
    required String userId,
    required String blockchainName,
    required String senderAddress,
    required String recipientAddress,
    required String amount,
    required String smartContractAddress,
  }) async {
    final txId = _uuid.v4();
    _pending[txId] = _PendingLocalSend(
      walletName: walletName,
      userId: userId,
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
      expiresAt:
          DateTime.now().add(const Duration(minutes: 15)).toIso8601String(),
      message: 'Prepared locally',
      success: true,
      transactionId: txId,
    );
  }

  /// مرحله تایید و امضای تراکنش (Double-Spend Safe).
  ///
  /// ## 🛡️ Defense-in-Depth: No Re-Signing
  ///
  /// اگر pending entry از قبل دارای [signedTransactionData] باشد (یعنی قبلاً
  /// امضا شده اما broadcast با خطا مواجه شده)، این متد مستقیماً به
  /// [retryBroadcast] می‌رود و **از امضای مجدد جلوگیری می‌کند**. این لایه
  /// دوم دفاعی است در برابر هرگونه retry خارجی که ممکن است در آینده اضافه شود.
  ///
  /// این متد:
  /// 1. احراز هویت بیومتریک انجام می‌دهد
  /// 2. بررسی می‌کند آیا تراکنش قبلاً امضا شده است (اگر بله → retryBroadcast)
  /// 3. منیمونیک را از SecureStorage می‌خواند (فقط در این scope)
  /// 4. تراکنش را امضا می‌کند و signed data را در pending ذخیره می‌کند
  /// 5. broadcast می‌کند (با retry داخلی idempotent)
  /// 6. پس از موفقیت، pending entry را پاک می‌کند
  /// 7. در صورت خطا در broadcast (اما موفقیت در sign)، pending entry با
  ///    signed data نگه داشته می‌شود برای retry بدون امضای مجدد
  /// 8. در صورت خطا در sign، pending entry پاک می‌شود (چیزی برای retry نیست)
  Future<String?> confirm({
    required String walletName,
    required String userId,
    required String blockchainName,
    required String recipientAddress,
    required String amount,
    required String smartContractAddress,
    String? transactionId,
  }) async {
    // 🛡️ Defense-in-Depth: اگر تراکنش قبلاً امضا شده باشد،
    // مستقیماً broadcast می‌کنیم بدون امضای مجدد.
    // این از double-spend جلوگیری می‌کند حتی اگر confirm() چندبار صدا زده شود.
    if (transactionId != null) {
      final existingPending = _pending[transactionId];
      if (existingPending != null && existingPending.isSigned) {
        SecureLog.i(
          'confirm() called for already-signed transaction $transactionId — '
          'skipping sign, going directly to idempotent broadcast. '
          '(Double-spend protection)',
        );
        return retryBroadcast(transactionId);
      }
    }

    final ok = await ServiceLocator.get<SecureKeyVault>().authenticateForSigning();
    if (!ok) return null;

    _PendingLocalSend? pending;
    if (transactionId != null) {
      pending = _pending[transactionId];
      // Don't remove yet — keep for potential retry
    }

    final chain = pending?.blockchainName ?? blockchainName;
    final recipient = pending?.recipientAddress ?? recipientAddress;
    final amt = pending?.amount ?? amount;
    final contract = pending?.smartContractAddress ?? smartContractAddress;
    final sender = pending?.senderAddress ?? '';
    final name = pending?.walletName ?? walletName;
    final uid = pending?.userId ?? userId;

    // منیمونیک فقط در این scope در دسترس است و پس از آن پاک می‌شود
    return MnemonicScope.use(
      () => ServiceLocator.get<SecureStorage>().getMnemonic(name, uid),
      callback: (mnemonic) async {
        SignedTransactionData? capturedSigned;

        try {
          // 🛡️ Sign + broadcast with onSigned callback to capture signed data
          final hash = await _wcSigner.send(
            mnemonic: mnemonic,
            blockchainName: chain,
            senderAddress: sender,
            recipient: recipient,
            amount: amt,
            smartContractAddress: contract,
            onSigned: (signedData) {
              capturedSigned = signedData;
              // Store signed data in pending for idempotent retry
              if (transactionId != null && _pending.containsKey(transactionId)) {
                _pending[transactionId]!.signedTransactionData = signedData;
              }
            },
          );

          if (hash != null && hash.isNotEmpty) {
            // ✅ Success: remove pending entry
            if (transactionId != null) {
              _pending.remove(transactionId);
            }
            return hash;
          }
          return null;
        } catch (e) {
          if (capturedSigned != null) {
            // ✅ Sign succeeded, broadcast failed.
            // Keep pending entry with signed data for idempotent retry.
            // 🛡️ No re-signing needed on retry — the signed bytes are stored.
            rethrow;
          }

          // ❌ Sign itself failed (e.g. mnemonic error, key derivation failure).
          // Remove pending entry — no signed data to retry with.
          if (transactionId != null) {
            _pending.remove(transactionId);
          }

          // Try EVM fallback before giving up
          final n = chain.toLowerCase();
          if (contract.isEmpty && _isEvm(n)) {
            return _evmFallback.sendNative(
              mnemonic: mnemonic,
              blockchainName: chain,
              recipient: recipient,
              amountEth: amt,
            );
          }

          rethrow;
        }
      },
    );
  }

  /// 🛡️ Idempotent broadcast retry — re-broadcasts without re-signing.
  ///
  /// Uses the signed transaction data captured during a previous [confirm]
  /// call. This is the "broadcast many" part of the "sign once, broadcast
  /// many" pattern used by all major crypto wallets.
  ///
  /// Returns the tx hash on success, or throws on failure.
  ///
  /// ⚠️ NEVER falls back to full re-confirm (re-sign). If signed data is
  /// not available, the user must create a new transaction from scratch.
  Future<String?> retryBroadcast(String transactionId) async {
    final pending = _pending[transactionId];
    if (pending == null) {
      throw StateError(
        'Transaction $transactionId has expired. '
        'Please create a new transaction.',
      );
    }

    final signedData = pending.signedTransactionData;
    if (signedData == null) {
      // 🛡️ Guard: signed data must exist. If it doesn't, the user needs
      // to create a fresh transaction. NEVER fall back to re-signing.
      _pending.remove(transactionId);
      throw StateError(
        'Signed transaction data is unavailable. '
        'Please create a new transaction from the Send screen.',
      );
    }

    // Check if this is ERC20 (handled by EvmTokenSigner)
    if (pending.smartContractAddress.isNotEmpty &&
        _isEvm(pending.blockchainName.toLowerCase())) {
      final hash = await _evmTokenSigner.retryErc20(signedData);
      if (hash.isNotEmpty) {
        _pending.remove(transactionId);
      }
      return hash;
    }

    // Route to WalletCoreSigner for all other chains
    final hash = await _wcSigner.retryBroadcast(signedData);
    if (hash.isNotEmpty) {
      _pending.remove(transactionId);
    }
    return hash;
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
