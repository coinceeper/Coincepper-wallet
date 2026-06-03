import 'dart:typed_data';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bip39/bip39.dart' as bip39;

import '../wallet/derivation/multi_chain_deriver.dart';

/// سرویس اصلی Web3 برای اتصال به blockchain
@Deprecated('Dev DEX/lab only. Production wallet uses WalletRepository and LocalSendFacade.')
class Web3Service {
  static Web3Service? _instance;
  static Web3Service get instance => _instance ??= Web3Service._();
  Web3Service._();

  late Web3Client _client;
  EthereumAddress? _userAddress;
  Credentials? _credentials;
  
  // Getters برای دسترسی از سرویس‌های دیگر
  Web3Client get client => _client;
  Credentials? get credentials => _credentials;
  
  // تنظیمات شبکه
  static const String _defaultRpcUrl = 'http://127.0.0.1:8545'; // Hardhat Local Network
  static const int _chainId = 31337; // Hardhat Local Network
  
  // آدرس قرارداد Router برای عملیات DEX
  String? _routerAddress;
  
  // Storage برای ذخیره اطلاعات
  static const _storage = FlutterSecureStorage();
  
  // ==================== INITIALIZATION ====================
  
  /// مقداردهی اولیه سرویس
  Future<void> initialize({String? customRpcUrl}) async {
    try {
      final rpcUrl = customRpcUrl ?? _defaultRpcUrl;
      _client = Web3Client(rpcUrl, http.Client());
      
      // بارگذاری کیف پول ذخیره شده
      await _loadWalletFromStorage();
      
      print('✅ Web3Service initialized successfully');
    } catch (e) {
      print('❌ Error initializing Web3Service: $e');
      rethrow;
    }
  }
  
  /// بارگذاری کیف پول از storage
  Future<void> _loadWalletFromStorage() async {
    try {
      final privateKeyHex = await _storage.read(key: 'web3_private_key');
      if (privateKeyHex != null) {
        await _setWalletFromPrivateKey(privateKeyHex);
      }
    } catch (e) {
      print('⚠️ Could not load wallet from storage: $e');
    }
  }
  
  // ==================== WALLET MANAGEMENT ====================
  
  /// ایجاد کیف پول جدید
  Future<Map<String, String>> createWallet() async {
    try {
      // تولید mnemonic جدید
      final mnemonic = bip39.generateMnemonic();
      
      final derived = await const MultiChainDeriver().deriveAll(mnemonic);
      final eth = derived['Ethereum']!;
      final privateKey = EthPrivateKey.fromHex(eth.privateKeyHexOrWif);
      _credentials = privateKey;
      _userAddress = EthereumAddress.fromHex(eth.publicAddress);
      
      await _storage.write(key: 'web3_private_key', value: eth.privateKeyHexOrWif);
      await _storage.write(key: 'web3_mnemonic', value: mnemonic);
      await _storage.write(key: 'web3_address', value: _userAddress!.hex);
      
      print('✅ New wallet created: ${_userAddress!.hex}');
      
      return {
        'address': _userAddress!.hex,
        'mnemonic': mnemonic,
        'privateKey': privateKey.privateKeyInt.toRadixString(16),
      };
    } catch (e) {
      print('❌ Error creating wallet: $e');
      rethrow;
    }
  }
  
  /// import کردن کیف پول از mnemonic
  Future<String> importWalletFromMnemonic(String mnemonic) async {
    try {
      // اعتبارسنجی mnemonic
      if (!bip39.validateMnemonic(mnemonic)) {
        throw Exception('Invalid mnemonic phrase');
      }
      
      final derived = await const MultiChainDeriver().deriveAll(mnemonic);
      final eth = derived['Ethereum']!;
      final privateKey = EthPrivateKey.fromHex(eth.privateKeyHexOrWif);
      _credentials = privateKey;
      _userAddress = EthereumAddress.fromHex(eth.publicAddress);
      
      await _storage.write(key: 'web3_private_key', value: eth.privateKeyHexOrWif);
      await _storage.write(key: 'web3_mnemonic', value: mnemonic);
      await _storage.write(key: 'web3_address', value: _userAddress!.hex);
      
      print('✅ Wallet imported: ${_userAddress!.hex}');
      
      return _userAddress!.hex;
    } catch (e) {
      print('❌ Error importing wallet: $e');
      rethrow;
    }
  }
  
  /// تنظیم کیف پول از private key
  Future<void> _setWalletFromPrivateKey(String privateKeyHex) async {
    try {
      final privateKey = EthPrivateKey.fromHex(privateKeyHex);
      _credentials = privateKey;
      _userAddress = await _credentials!.extractAddress();
      
      print('✅ Wallet loaded: ${_userAddress!.hex}');
    } catch (e) {
      print('❌ Error setting wallet from private key: $e');
      rethrow;
    }
  }
  
  /// دریافت آدرس کیف پول فعلی
  String? get walletAddress => _userAddress?.hex;
  
  /// آیا کیف پول متصل است
  bool get isWalletConnected => _userAddress != null && _credentials != null;
  
  /// کیف پول تست Hardhat
  static const String testWalletPrivateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
  
  /// اتصال به کیف پول تست Hardhat
  Future<void> connectTestWallet() async {
    await _setWalletFromPrivateKey(testWalletPrivateKey);
  }
  
  // ==================== BLOCKCHAIN OPERATIONS ====================
  
  /// دریافت موجودی ETH/MATIC
  Future<double> getNativeBalance() async {
    if (_userAddress == null) throw Exception('Wallet not connected');
    
    try {
      final balance = await _client.getBalance(_userAddress!);
      return balance.getValueInUnit(EtherUnit.ether);
    } catch (e) {
      print('❌ Error getting native balance: $e');
      rethrow;
    }
  }
  
  /// دریافت موجودی توکن ERC20
  Future<double> getTokenBalance(String tokenAddress, {int decimals = 18}) async {
    if (_userAddress == null) throw Exception('Wallet not connected');
    
    try {
      final contract = await _getERC20Contract(tokenAddress);
      final balance = await _client.call(
        contract: contract,
        function: contract.function('balanceOf'),
        params: [_userAddress!],
      );
      
      final balanceBigInt = balance.first as BigInt;
      return balanceBigInt.toDouble() / (BigInt.from(10).pow(decimals).toDouble());
    } catch (e) {
      print('❌ Error getting token balance: $e');
      rethrow;
    }
  }
  
  /// ارسال تراکنش
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
      
      final txHash = await _client.sendTransaction(
        _credentials!,
        transaction,
        chainId: _chainId,
      );
      
      print('✅ Transaction sent: $txHash');
      return txHash;
    } catch (e) {
      print('❌ Error sending transaction: $e');
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
      
      final txHash = await _client.sendTransaction(
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
      
      print('✅ Token approved: $txHash');
      return txHash;
    } catch (e) {
      print('❌ Error approving token: $e');
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
      
      final txHash = await _client.sendTransaction(
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
      
      print('✅ Token transferred: $txHash');
      return txHash;
    } catch (e) {
      print('❌ Error transferring token: $e');
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
    // Kept for compatibility with callers; not used by this service yet.
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
    
    try {
      // اینجا باید ABI و منطق swap اصلی اضافه شود
      throw UnimplementedError('Swap function will be implemented with actual contract ABI');
    } catch (e) {
      print('❌ Error swapping tokens: $e');
      rethrow;
    }
  }
  
  // ==================== UTILITY FUNCTIONS ====================
  
  /// دریافت وضعیت تراکنش
  Future<TransactionReceipt?> getTransactionReceipt(String txHash) async {
    try {
      return await _client.getTransactionReceipt(txHash);
    } catch (e) {
      print('❌ Error getting transaction receipt: $e');
      return null;
    }
  }
  
  /// منتظر ماندن برای confirm شدن تراکنش
  Future<TransactionReceipt> waitForTransaction(String txHash) async {
    TransactionReceipt? receipt;
    int attempts = 0;
    const maxAttempts = 30; // 30 تلاش (حدود 5 دقیقه)
    
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
  
  /// پاک کردن کیف پول
  Future<void> clearWallet() async {
    try {
      await _storage.delete(key: 'web3_private_key');
      await _storage.delete(key: 'web3_mnemonic');
      await _storage.delete(key: 'web3_address');
      
      _credentials = null;
      _userAddress = null;
      
      print('✅ Wallet cleared');
    } catch (e) {
      print('❌ Error clearing wallet: $e');
      rethrow;
    }
  }
  
  /// Dispose کردن client
  void dispose() {
    _client.dispose();
  }
} 