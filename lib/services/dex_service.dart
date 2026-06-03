import 'dart:math';
import 'package:web3dart/web3dart.dart';
import 'web3_service.dart';

/// سرویس DEX برای تعامل با قرارداد توکن اصلی (ERC20)
class DexService {
  static DexService? _instance;
  static DexService get instance => _instance ??= DexService._();
  DexService._();

  final Web3Service _web3 = Web3Service.instance;
  
  // آدرس‌های قراردادها از deployment شده (Hardhat Local Network)
  String? _dexTokenAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  String? _routerAddress = "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9";
  String? _quoterAddress = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";
  
  // ABI حداقلی ERC20 برای توکن تست / محلی
  final String _dexTokenAbi = '''[
    {
      "inputs": [{"name": "account", "type": "address"}],
      "name": "balanceOf",
      "outputs": [{"name": "", "type": "uint256"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"name": "to", "type": "address"}, {"name": "amount", "type": "uint256"}],
      "name": "mint",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"name": "amount", "type": "uint256"}],
      "name": "burn",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"name": "spender", "type": "address"}, {"name": "value", "type": "uint256"}],
      "name": "approve",
      "outputs": [{"name": "", "type": "bool"}],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"name": "to", "type": "address"}, {"name": "value", "type": "uint256"}],
      "name": "transfer",
      "outputs": [{"name": "", "type": "bool"}],
      "stateMutability": "nonpayable",
      "type": "function"
    }
  ]''';
  
  final String _routerAbi = '''[
    {
      "inputs": [
        {"name": "_tokenIn", "type": "address"},
        {"name": "_tokenOut", "type": "address"},
        {"name": "_amountIn", "type": "uint256"},
        {"name": "_minAmountOut", "type": "uint256"}
      ],
      "name": "executeSwap",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {"name": "_token", "type": "address"},
        {"name": "_amount", "type": "uint256"}
      ],
      "name": "addLiquidity",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    }
  ]''';
  
  final String _quoterAbi = '''[
    {
      "inputs": [
        {"name": "_tokenIn", "type": "address"},
        {"name": "_tokenOut", "type": "address"},
        {"name": "_amountIn", "type": "uint256"}
      ],
      "name": "getSwapQuote",
      "outputs": [
        {"name": "amountOut", "type": "uint256"},
        {"name": "priceImpact", "type": "uint256"}
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [
        {"name": "_token", "type": "address"},
        {"name": "_price", "type": "uint256"}
      ],
      "name": "updatePrice",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    }
  ]''';
  
  // ==================== INITIALIZATION ====================
  
  /// تنظیم آدرس‌های قراردادها
  void setContractAddresses({
    required String dexToken,
    required String poolFactory,
    required String router,
    required String quoter,
  }) {
    _dexTokenAddress = dexToken;
    _routerAddress = router;
    _quoterAddress = quoter;
    
    // تنظیم آدرس‌ها در Web3Service
    _web3.setContractAddresses(
      dexToken: dexToken,
      poolFactory: poolFactory,
      router: router,
    );
    
    print('✅ DEX contract addresses set');
  }
  
  // ==================== TOKEN OPERATIONS ====================
  
  /// دریافت موجودی توکن اصلی DEX
  Future<double> getDexTokenBalance() async {
    if (_dexTokenAddress == null) throw Exception('DEX token address not set');
    return await _web3.getTokenBalance(_dexTokenAddress!, decimals: 18);
  }
  
  /// دریافت تخفیف fee کاربر
  Future<double> getUserFeeDiscount() async {
    if (!_web3.isWalletConnected) throw Exception('Wallet not connected');
    if (_dexTokenAddress == null) throw Exception('DEX token address not set');
    
    try {
             final contract = _getDexTokenContract();
       final client = _web3.client;
       final userAddress = EthereumAddress.fromHex(_web3.walletAddress!);
      
      final result = await client.call(
        contract: contract,
        function: contract.function('getFeeDiscount'),
        params: [userAddress],
      );
      
      final discountBasisPoints = result.first as BigInt;
      return discountBasisPoints.toDouble() / 10000; // Convert from basis points to percentage
    } catch (e) {
      print('❌ Error getting fee discount: $e');
      return 0.0;
    }
  }
  
  /// lock کردن توکن اصلی DEX
  Future<String> lockDexTokens({
    required double amount,
    required Duration duration,
    bool autoExtend = false,
  }) async {
    if (!_web3.isWalletConnected) throw Exception('Wallet not connected');
    if (_dexTokenAddress == null) throw Exception('DEX token address not set');
    
    try {
             final contract = _getDexTokenContract();
       final client = _web3.client;
       final credentials = _web3.credentials!;
      
      final amountWei = BigInt.from(amount * pow(10, 18));
      final durationSeconds = BigInt.from(duration.inSeconds);
      
      final txHash = await client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract,
          function: contract.function('lockTokens'),
          parameters: [amountWei, durationSeconds, autoExtend],
        ),
        chainId: 80001, // Polygon Mumbai
      );
      
      print('✅ DEX tokens locked: $txHash');
      return txHash;
    } catch (e) {
      print('❌ Error locking DEX tokens: $e');
      rethrow;
    }
  }
  
  // ==================== SWAP OPERATIONS ====================
  
  /// دریافت قیمت swap (quote)
  Future<SwapQuote> getSwapQuote({
    required String tokenIn,
    required String tokenOut,
    required double amountIn,
  }) async {
    if (_quoterAddress == null) throw Exception('Quoter address not set');
    
    try {
             final contract = _getQuoterContract();
       final client = _web3.client;
      
      final tokenInAddress = EthereumAddress.fromHex(tokenIn);
      final tokenOutAddress = EthereumAddress.fromHex(tokenOut);
      final amountInWei = BigInt.from(amountIn * pow(10, 18));
      
      final result = await client.call(
        contract: contract,
        function: contract.function('quoteExactInputSingle'),
        params: [tokenInAddress, tokenOutAddress, amountInWei],
      );
      
      final amountOutWei = result.first as BigInt;
      final amountOut = amountOutWei.toDouble() / pow(10, 18);
      
      // محاسبه نرخ تبدیل
      final rate = amountOut / amountIn;
      
      // محاسبه fee (mock - باید از contract دریافت شود)
      const baseFee = 0.003; // 0.3%
      final discount = await getUserFeeDiscount();
      final effectiveFee = baseFee * (1 - discount);
      
      // محاسبه price impact (تقریبی)
      final priceImpact = _calculatePriceImpact(amountIn, rate);
      
      return SwapQuote(
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        amountIn: amountIn,
        amountOut: amountOut,
        rate: rate,
        fee: effectiveFee,
        priceImpact: priceImpact,
        minimumReceived: amountOut * 0.995, // 0.5% slippage
      );
    } catch (e) {
      print('❌ Error getting swap quote: $e');
      rethrow;
    }
  }
  
  /// انجام swap
  Future<String> executeSwap({
    required String tokenIn,
    required String tokenOut,
    required double amountIn,
    required double amountOutMin,
    double slippageTolerance = 0.005, // 0.5%
  }) async {
    if (!_web3.isWalletConnected) throw Exception('Wallet not connected');
    if (_routerAddress == null) throw Exception('Router address not set');
    
    try {
      final userAddress = _web3.walletAddress!;
      
      // 1. ابتدا approve کردن token
      final amountInWei = BigInt.from(amountIn * pow(10, 18));
      await _web3.approveToken(
        tokenAddress: tokenIn,
        spenderAddress: _routerAddress!,
        amount: amountInWei,
      );
      
      // 2. انجام swap
      final contract = _getRouterContract();
      final client = _web3.client;
      final credentials = _web3.credentials!;
      
      final tokenInAddress = EthereumAddress.fromHex(tokenIn);
      final tokenOutAddress = EthereumAddress.fromHex(tokenOut);
      final amountOutMinWei = BigInt.from(amountOutMin * pow(10, 18));
      final recipientAddress = EthereumAddress.fromHex(userAddress);
      
      final txHash = await client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract,
          function: contract.function('exactInputSingle'),
          parameters: [
            tokenInAddress,
            tokenOutAddress,
            amountInWei,
            amountOutMinWei,
            recipientAddress,
          ],
        ),
        chainId: 80001, // Polygon Mumbai
      );
      
      print('✅ Swap executed: $txHash');
      return txHash;
    } catch (e) {
      print('❌ Error executing swap: $e');
      rethrow;
    }
  }
  
  // ==================== LIQUIDITY OPERATIONS ====================
  
  /// اضافه کردن نقدینگی (ساده شده)
  Future<String> addLiquidity({
    required String token0,
    required String token1,
    required double amount0,
    required double amount1,
  }) async {
    if (!_web3.isWalletConnected) throw Exception('Wallet not connected');
    
    try {
      // این تابع باید با Pool Manager contract پیاده‌سازی شود
      throw UnimplementedError('Add liquidity will be implemented with Pool Manager contract');
    } catch (e) {
      print('❌ Error adding liquidity: $e');
      rethrow;
    }
  }
  
  /// حذف نقدینگی
  Future<String> removeLiquidity({
    required String poolAddress,
    required double liquidityAmount,
  }) async {
    if (!_web3.isWalletConnected) throw Exception('Wallet not connected');
    
    try {
      // این تابع باید با Pool Manager contract پیاده‌سازی شود
      throw UnimplementedError('Remove liquidity will be implemented with Pool Manager contract');
    } catch (e) {
      print('❌ Error removing liquidity: $e');
      rethrow;
    }
  }
  
  // ==================== HELPER FUNCTIONS ====================
  
  DeployedContract _getDexTokenContract() {
    if (_dexTokenAddress == null) throw Exception('DEX token address not set');
    final contractAbi = ContractAbi.fromJson(_dexTokenAbi, 'ERC20');
    return DeployedContract(contractAbi, EthereumAddress.fromHex(_dexTokenAddress!));
  }
  
  /// دریافت contract Router
  DeployedContract _getRouterContract() {
    if (_routerAddress == null) throw Exception('Router address not set');
    final contractAbi = ContractAbi.fromJson(_routerAbi, 'Router');
    return DeployedContract(contractAbi, EthereumAddress.fromHex(_routerAddress!));
  }
  
  /// دریافت contract Quoter
  DeployedContract _getQuoterContract() {
    if (_quoterAddress == null) throw Exception('Quoter address not set');
    final contractAbi = ContractAbi.fromJson(_quoterAbi, 'Quoter');
    return DeployedContract(contractAbi, EthereumAddress.fromHex(_quoterAddress!));
  }
  
  /// محاسبه price impact
  double _calculatePriceImpact(double amountIn, double rate) {
    // محاسبه ساده price impact بر اساس نسبت amount به liquidity pool
    // در پیاده‌سازی واقعی باید از pool reserves استفاده شود
    final liquidityRatio = amountIn / 100000; // فرض liquidity pool
    return liquidityRatio * 0.1; // تقریب ساده
  }
  
  // ==================== MOCK DATA ====================
  
  /// دریافت لیست توکن‌های موجود (mock data)
  List<DexToken> getAvailableTokens() {
    return [
      DexToken(
        address: _dexTokenAddress ?? '0x0000000000000000000000000000000000000000',
        symbol: 'CCKP',
        name: 'CoinCeeper Pool Token',
        decimals: 18,
        logoUrl: 'assets/logo.png',
      ),
      DexToken(
        address: '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270', // WMATIC on Polygon
        symbol: 'WMATIC',
        name: 'Wrapped MATIC',
        decimals: 18,
        logoUrl: 'assets/images/matic-logo.png',
      ),
      DexToken(
        address: '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174', // USDC on Polygon
        symbol: 'USDC',
        name: 'USD Coin',
        decimals: 6,
        logoUrl: 'assets/images/usdc-logo.png',
      ),
    ];
  }
}

// ==================== DATA MODELS ====================

/// مدل نتیجه quote
class SwapQuote {
  final String tokenIn;
  final String tokenOut;
  final double amountIn;
  final double amountOut;
  final double rate;
  final double fee;
  final double priceImpact;
  final double minimumReceived;
  
  SwapQuote({
    required this.tokenIn,
    required this.tokenOut,
    required this.amountIn,
    required this.amountOut,
    required this.rate,
    required this.fee,
    required this.priceImpact,
    required this.minimumReceived,
  });
  
  Map<String, dynamic> toJson() => {
    'tokenIn': tokenIn,
    'tokenOut': tokenOut,
    'amountIn': amountIn,
    'amountOut': amountOut,
    'rate': rate,
    'fee': fee,
    'priceImpact': priceImpact,
    'minimumReceived': minimumReceived,
  };
}

/// مدل توکن DEX
class DexToken {
  final String address;
  final String symbol;
  final String name;
  final int decimals;
  final String logoUrl;
  
  DexToken({
    required this.address,
    required this.symbol,
    required this.name,
    required this.decimals,
    required this.logoUrl,
  });
  
  Map<String, dynamic> toJson() => {
    'address': address,
    'symbol': symbol,
    'name': name,
    'decimals': decimals,
    'logoUrl': logoUrl,
  };
}
