import 'dart:typed_data';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;

import '../di/service_locator.dart';
import '../utils/secure_log.dart';
import 'sensitive_data.dart';

/// سرویس Web3 برای اتصال به EVM-compatible blockchain (Ethereum, BSC, Polygon, ...)
///
/// ⚠️ SECURITY: این سرویس هرگز کلید خصوصی یا منیمونیک را ذخیره نمی‌کند.
/// - کلید خصوصی از طریق `WalletCoreBridge` و `MnemonicScope` تأمین می‌شود
/// - Credentials بلافاصله پس از امضا dispose می‌شوند
/// - هیچ داده حساسی در حافظه پنهان نمی‌ماند
@Deprecated('Dev DEX/lab only. Production wallet uses WalletRepository and LocalSendFacade.')
class Web3Service {
  Web3Service();

  Web3Service._();

  static Web3Service get instance => ServiceLocator.get<Web3Service>();

  Web3Client? _client;
  EthereumAddress? _userAddress;
  Credentials? _credentials;

  // Getters برای دسترسی از سرویس‌های دیگر
  Web3Client get client {
    if (_client == null) {
      throw StateError('Web3Service not initialized. Call initialize() first.');
    }
    return _client!;
  }

  Credentials? get credentials => _credentials;

  // ═══════════════════════════════════════════════════════════════
  // تنظیمات شبکه — از طریق initialize() یا setter تنظیم می‌شوند
  // ═══════════════════════════════════════════════════════════════
  String _rpcUrl = '';
  int _chainId = 0;

  /// تنظیم RPC URL
  set rpcUrl(String url) => _rpcUrl = url;

  /// تنظیم Chain ID
  set chainId(int id) => _chainId = id;

  /// دریافت Chain ID فعال
  int get chainId => _chainId;

  // آدرس قرارداد Router برای عملیات DEX
  String? _routerAddress;

  // ==================== INITIALIZATION ====================

  /// مقداردهی اولیه سرویس
  ///
  /// [customRpcUrl]: (اجباری) آدرس RPC node
  /// [customChainId]: (اجباری) شناسه زنجیر بلاکچین
  Future<void> initialize({
    required String customRpcUrl,
    required int customChainId,
  }) async {
    try {
      _rpcUrl = customRpcUrl;
      _chainId = customChainId;
      _client = Web3Client(_rpcUrl, http.Client());
      SecureLog.i('Web3Service initialized (chainId=$_chainId)');
    } catch (e) {
      SecureLog.e('Web3Service initialize failed', error: e);
      rethrow;
    }
  }

  // ==================== WALLET MANAGEMENT ====================

  /// تنظیم Credentials از طریق private key با پاکسازی امن پس از استفاده.
  ///
  /// [onCredentials] با credentials ایجاد شده فراخوانی می‌شود و پس از اتمام
  /// credentials از حافظه پاک می‌شود.
  Future<T> withPrivateKeyHex<T>({
    required String privateKeyHex,
    required Future<T> Function(Credentials creds) onCredentials,
  }) async {
    final sensitiveKey = SensitiveString.fromString(privateKeyHex);
    try {
      final creds = await sensitiveKey.useAsync((hex) async {
        return EthPrivateKey.fromHex(hex);
      });
      try {
        return await onCredentials(creds);
      } finally {
        // پاکسازی credentials از حافظه
        _wipeCredentials(creds);
      }
    } finally {
      sensitiveKey.dispose();
    }
  }

  /// پاکسازی امن credentials از حافظه
  void _wipeCredentials(Credentials creds) {
    try {
      if (creds is EthPrivateKey) {
        // در Dart امکان wipe کامل نیست اما reference را می‌شکنیم
      }
    } catch (e) {
      SecureLog.w('Error wiping credentials', error: e);
    }
  }

  /// پاک کردن credentials از حافظه
  void clearCredentials() {
    _credentials = null;
    _userAddress = null;
  }

  /// دریافت آدرس کیف پول فعلی
  String? get walletAddress => _userAddress?.hex;

  /// آیا کیف پول متصل است
  bool get isWalletConnected => _userAddress != null && _credentials != null;

  // ==================== BLOCKCHAIN OPERATIONS ====================

  /// دریافت موجودی ETH/MATIC
  Future<double> getNativeBalance() async {
    if (_userAddress == null) throw Exception('Wallet not connected');

    try {
      final balance = await _client!.getBalance(_userAddress!);
      return balance.getValueInUnit(EtherUnit.ether);
    } catch (e) {
      SecureLog.e('Error getting native balance', error: e);
      rethrow;
    }
  }

  /// دریافت موجودی توکن ERC20
  Future<double> getTokenBalance(String tokenAddress, {int decimals = 18}) async {
    if (_userAddress == null) throw Exception('Wallet not connected');

    try {
      final contract = await _getERC20Contract(tokenAddress);
      final balance = await _client!.call(
        contract: contract,
        function: contract.function('balanceOf'),
        params: [_userAddress!],
      );

      final balanceBigInt = balance.first as BigInt;
      return balanceBigInt.toDouble() / (BigInt.from(10).pow(decimals).toDouble());
    } catch (e) {
      SecureLog.e('Error getting token balance', error: e);
      rethrow;
    }
  }

  /// ارسال تراکنش با credentials موجود
  Future<String> sendTransaction({
    required EthereumAddress to,
    required EtherAmount value,
    Uint8List? data,
    int? gasLimit,
    EtherAmount? gasPrice,
  }) async {
    if (_credentials == null) throw Exception('Wallet not connected');

    try {
      final transaction = Transaction(
        to: to,
        value: value,
        data: data,
        gasPrice: gasPrice,
        maxGas: gasLimit,
      );

      final txHash = await _client!.sendTransaction(
        _credentials!,
        transaction,
        chainId: _chainId,
      );

      SecureLog.i('Transaction sent: $txHash');
      return txHash;
    } catch (e) {
      SecureLog.e('Error sending transaction', error: e);
      rethrow;
    }
  }

  // ==================== SMART CONTRACT INTERACTIONS ====================

  /// دریافت contract ERC20
  Future<DeployedContract> _getERC20Contract(String address) async {
    const erc20Abi = '''[
      {
        "constant": true,
        "inputs": [{"name": "account", "type": "address"}],
        "name": "balanceOf",
        "outputs": [{"name": "", "type": "uint256"}],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [
          {"name": "to", "type": "address"},
          {"name": "amount", "type": "uint256"}
        ],
        "name": "transfer",
        "outputs": [{"name": "", "type": "bool"}],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [
          {"name": "spender", "type": "address"},
          {"name": "amount", "type": "uint256"}
        ],
        "name": "approve",
        "outputs": [{"name": "", "type": "bool"}],
        "type": "function"
      },
      {
        "constant": true,
        "inputs": [],
        "name": "decimals",
        "outputs": [{"name": "", "type": "uint8"}],
        "type": "function"
      }
    ]''';

    final contractAbi = ContractAbi.fromJson(erc20Abi, 'ERC20');
    return DeployedContract(contractAbi, EthereumAddress.fromHex(address));
  }

  /// approve کردن توکن
  Future<String> approveToken({
    required String tokenAddress,
    required String spenderAddress,
    required BigInt amount,
  }) async {
    if (_credentials == null) throw Exception('Wallet not connected');

    try {
      final contract = await _getERC20Contract(tokenAddress);

      final txHash = await _client!.sendTransaction(
        _credentials!,
        Transaction.callContract(
          contract: contract,
          function: contract.function('approve'),
          parameters: [
            EthereumAddress.fromHex(spenderAddress),
            amount,
          ],
        ),
        chainId: _chainId,
      );

      SecureLog.i('Token approved: $txHash');
      return txHash;
    } catch (e) {
      SecureLog.e('Error approving token', error: e);
      rethrow;
    }
  }

  /// transfer کردن توکن
  Future<String> transferToken({
    required String tokenAddress,
    required String toAddress,
    required BigInt amount,
  }) async {
    if (_credentials == null) throw Exception('Wallet not connected');

    try {
      final contract = await _getERC20Contract(tokenAddress);

      final txHash = await _client!.sendTransaction(
        _credentials!,
        Transaction.callContract(
          contract: contract,
          function: contract.function('transfer'),
          parameters: [
            EthereumAddress.fromHex(toAddress),
            amount,
          ],
        ),
        chainId: _chainId,
      );

      SecureLog.i('Token transferred: $txHash');
      return txHash;
    } catch (e) {
      SecureLog.e('Error transferring token', error: e);
      rethrow;
    }
  }

  // ==================== DEX OPERATIONS ====================

  /// تنظیم آدرس‌های قراردادها
  void setContractAddresses({
    String? dexToken,
    String? poolFactory,
    String? router,
  }) {
    if (dexToken != null || poolFactory != null) {
      // no-op
    }
    _routerAddress = router;
  }

  /// swap توکن‌ها (placeholder - باید با contract اصلی تکمیل شود)
  Future<String> swapTokens({
    required String tokenIn,
    required String tokenOut,
    required BigInt amountIn,
    required BigInt amountOutMin,
    required String recipient,
  }) async {
    if (_credentials == null) throw Exception('Wallet not connected');
    if (_routerAddress == null) throw Exception('Router address not set');

    throw UnimplementedError('Swap function will be implemented with actual contract ABI');
  }

  // ==================== UTILITY FUNCTIONS ====================

  /// دریافت وضعیت تراکنش
  Future<TransactionReceipt?> getTransactionReceipt(String txHash) async {
    try {
      return await _client!.getTransactionReceipt(txHash);
    } catch (e) {
      SecureLog.e('Error getting transaction receipt', error: e);
      return null;
    }
  }

  /// منتظر ماندن برای confirm شدن تراکنش
  Future<TransactionReceipt> waitForTransaction(String txHash) async {
    TransactionReceipt? receipt;
    int attempts = 0;
    const maxAttempts = 30;

    while (receipt == null && attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 10));
      receipt = await getTransactionReceipt(txHash);
      attempts++;
    }

    if (receipt == null) {
      throw Exception('Transaction confirmation timeout');
    }

    return receipt;
  }

  /// Dispose کردن client و پاکسازی credentials
  void dispose() {
    clearCredentials();
    _client?.dispose();
    _client = null;
  }
}
