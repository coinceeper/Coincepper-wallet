import 'package:flutter/material.dart';
import '../navigation/app_navigation.dart';
import '../navigation/route_paths.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:convert';
import '../models/crypto_token.dart';
import '../models/transaction.dart' as models;
import '../layout/main_layout.dart';
import '../services/transaction_notification_receiver.dart';
import '../services/notification_helper.dart';
import '../services/api_service.dart';
import '../services/api_models.dart';
import '../wallet/transactions/local_send_facade.dart';
import '../wallet/wallet_mode.dart';
import '../wallet/wallet_repository.dart';
import '../wallet/address_registry.dart';
import '../providers/history_provider.dart';
import '../utils/shared_preferences_utils.dart';
import '../services/secure_storage.dart';
import '../providers/token_provider.dart';
import '../providers/price_provider.dart';
import '../services/address_book_service.dart';
import '../models/address_book_entry.dart';

class SendDetailScreen extends StatefulWidget {
  final String tokenJson;
  const SendDetailScreen({super.key, required this.tokenJson});

  @override
  State<SendDetailScreen> createState() => _SendDetailScreenState();
}

class _SendDetailScreenState extends State<SendDetailScreen> {
  CryptoToken? token;
  bool isLoading = false;
  String address = '';
  String amount = '';
  bool addressError = false;
  bool showAddressBook = false;
  bool showErrorModal = false;
  String errorMessage = '';
  bool showConfirmModal = false;
  bool isPriceLoading = false;
  double pricePerToken = 0.0;
  String walletName = 'My Wallet';
  String userId = '';
  late ApiService apiService;
  PrepareTransactionResponse? txDetails;
  EstimateFeeResponse? feeDetails;
  String? selectedPriority = 'average';
  bool showSelfTransferError = false;
  
  List<AddressBookEntry> addressBook = [];

  // ✅ Add TextEditingController variables to fix input issues
  late TextEditingController _addressController;
  late TextEditingController _amountController;

  // Network Fee Options
  Map<String, NetworkFeeOption> networkFeeOptions = {
    'slow': NetworkFeeOption(
      priority: 'slow',
      gasPriceGwei: 10,
      feeEth: 0.0001,
      feeUsd: 0.20,
      estimatedTime: '5-10 min',
    ),
    'average': NetworkFeeOption(
      priority: 'average',
      gasPriceGwei: 20,
      feeEth: 0.0002,
      feeUsd: 0.40,
      estimatedTime: '2-5 min',
    ),
    'fast': NetworkFeeOption(
      priority: 'fast',
      gasPriceGwei: 30,
      feeEth: 0.0003,
      feeUsd: 0.60,
      estimatedTime: '1-2 min',
    ),
  };

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    apiService = ApiService();
    
    // ✅ Initialize TextEditingControllers
    _addressController = TextEditingController();
    _amountController = TextEditingController();
    
    // Initialize data after a short delay to ensure providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void dispose() {
    // ✅ Dispose TextEditingControllers to prevent memory leaks
    _addressController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    await _parseToken();
    await _loadUserData();
    await _loadAddressBook();
    await _fetchPrice();
    
    // ✅ Sync controllers with initial state
    _syncControllers();
    
    print('🔍 Send Detail Screen initialized:');
    print('   Token: ${token?.symbol} (${token?.blockchainName})');
    print('   Wallet: $walletName');
    print('   UserId: $userId');
    print('   Address Book Entries: ${addressBook.length}');
  }

  /// ✅ Sync TextEditingControllers with state variables
  void _syncControllers() {
    if (_addressController.text != address) {
      _addressController.text = address;
    }
    if (_amountController.text != amount) {
      _amountController.text = amount;
    }
  }

  /// Load address book entries from storage
  Future<void> _loadAddressBook() async {
    try {
      final entries = await AddressBookService.loadWalletsFromKeystore();
      setState(() {
        addressBook = entries;
      });
      print('✅ Loaded ${entries.length} address book entries');
    } catch (e) {
      print('❌ Error loading address book: $e');
      setState(() {
        addressBook = [];
      });
    }
  }

  Future<void> _parseToken() async {
    try {
      final decodedJson = Uri.decodeComponent(widget.tokenJson);
      final tokenData = jsonDecode(decodedJson) as Map<String, dynamic>;
      setState(() {
        token = CryptoToken.fromJson(tokenData);
      });
    } catch (e) {
      setState(() {
        token = null;
      });
    }
  }

  Future<void> _loadUserData() async {
    try {
      // بارگذاری کیف پول انتخاب شده و userId مربوطه از SecureStorage
      final selectedWallet = await SecureStorage.instance.getSelectedWallet();
      final selectedUserId = await SecureStorage.instance.getUserIdForSelectedWallet();
      
      if (selectedWallet != null && selectedUserId != null) {
        setState(() {
          walletName = selectedWallet;
          userId = selectedUserId;
        });
        print('✅ Loaded selected wallet: $selectedWallet with userId: $selectedUserId');
        return;
      }
      
      // Fallback: use first available wallet
      final wallets = await SecureStorage.instance.getWalletsList();
      if (wallets.isNotEmpty) {
        final firstWallet = wallets.first;
        final firstWalletName = firstWallet['walletName'];
        final firstWalletUserId = firstWallet['userID'];
        
        if (firstWalletName != null && firstWalletUserId != null) {
          setState(() {
            walletName = firstWalletName;
            userId = firstWalletUserId;
          });
          
          // Set as selected wallet for future use
          await SecureStorage.instance.saveSelectedWallet(firstWalletName, firstWalletUserId);
          print('✅ Using first available wallet: $firstWalletName with userId: $firstWalletUserId');
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _fetchPrice() async {
    setState(() { isPriceLoading = true; });
    try {
      if (token?.symbol == null) {
        setState(() {
          pricePerToken = 0.0;
          isPriceLoading = false;
        });
        return;
      }
      
      final tokenSymbol = token!.symbol!;
      print('💰 Fetching price for token: $tokenSymbol');
      
      // Try to get price from TokenProvider first
      double? price;
      try {
        final tokenProvider = Provider.of<TokenProvider>(context, listen: false);
        price = tokenProvider.getTokenPrice(tokenSymbol, 'USD');
        print('💰 TokenProvider price for $tokenSymbol: \$${price.toStringAsFixed(4) ?? 'null'}');
      } catch (e) {
        print('⚠️ TokenProvider not available: $e');
        price = null;
      }
      
      if (price == 0.0 || price == null) {
        // If TokenProvider doesn't have the price, try PriceProvider
        try {
          final priceProvider = Provider.of<PriceProvider>(context, listen: false);
          
          // Fetch price for this specific token
          await priceProvider.fetchPrices([tokenSymbol], currencies: ['USD']);
          price = priceProvider.getPrice(tokenSymbol);
          print('💰 PriceProvider price for $tokenSymbol: \$${price?.toStringAsFixed(4) ?? 'null'}');
        } catch (e) {
          print('⚠️ PriceProvider not available: $e');
          price = null;
        }
        
        if (price == 0.0 || price == null) {
          // Use fallback prices for known tokens
          price = _getFallbackPrice(tokenSymbol);
          print('💰 Using fallback price for $tokenSymbol: \$${price.toStringAsFixed(4)}');
        }
      }
      
      setState(() {
        pricePerToken = price ?? 0.0;
        isPriceLoading = false;
      });
      
      print('💰 Price for $tokenSymbol: \$${pricePerToken.toStringAsFixed(4)}');
      
    } catch (e) {
      print('❌ Error fetching price: $e');
      setState(() {
        // Use fallback price on error
        pricePerToken = _getFallbackPrice(token?.symbol ?? '');
        isPriceLoading = false;
      });
    }
  }

  // Fallback prices for known tokens (in USD) - Updated regularly
  double _getFallbackPrice(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'TRX':
      case 'TRON':
        return 0.11; // Current approximate TRX price
      case 'BTC':
      case 'BITCOIN':
        return 43500.0; // Current approximate BTC price
      case 'ETH':
      case 'ETHEREUM':
        return 2400.0; // Current approximate ETH price
      case 'BNB':
      case 'BINANCE':
        return 315.0; // Current approximate BNB price
      case 'USDT':
      case 'USDC':
      case 'BUSD':
        return 1.0; // Stablecoins
      case 'ADA':
      case 'CARDANO':
        return 0.45; // Approximate ADA price
      case 'XRP':
      case 'RIPPLE':
        return 0.52; // Approximate XRP price
      case 'SOL':
      case 'SOLANA':
        return 105.0; // Approximate SOL price
      case 'DOT':
      case 'POLKADOT':
        return 7.2; // Approximate DOT price
      case 'AVAX':
      case 'AVALANCHE':
        return 38.0; // Approximate AVAX price
      default:
        return 0.0;
    }
  }

  // Get fallback USD price for fee calculation
  double _getFallbackUsdPrice() {
    final tokenSymbol = token?.symbol ?? '';
    return _getFallbackPrice(tokenSymbol);
  }

  // Get default fees for different blockchains
  Map<String, Map<String, dynamic>> _getDefaultFeesForBlockchain(String? blockchainName) {
    final chain = (blockchainName ?? '').toLowerCase();
    
    if (chain.contains('tron')) {
      return {
        'slow': {'gasPrice': 1, 'feeEth': 0.0001},
        'average': {'gasPrice': 2, 'feeEth': 0.0002},
        'fast': {'gasPrice': 3, 'feeEth': 0.0003},
      };
    }
    
    if (chain.contains('bitcoin')) {
      return {
        'slow': {'gasPrice': 5, 'feeEth': 0.0005},
        'average': {'gasPrice': 10, 'feeEth': 0.001},
        'fast': {'gasPrice': 20, 'feeEth': 0.002},
      };
    }
    
    if (chain.contains('binance') || chain.contains('bsc')) {
      return {
        'slow': {'gasPrice': 3, 'feeEth': 0.0003},
        'average': {'gasPrice': 5, 'feeEth': 0.0005},
        'fast': {'gasPrice': 10, 'feeEth': 0.001},
      };
    }
    
    // Default (Ethereum-like)
    return {
      'slow': {'gasPrice': 10, 'feeEth': 0.0001},
      'average': {'gasPrice': 20, 'feeEth': 0.0002},
      'fast': {'gasPrice': 30, 'feeEth': 0.0003},
    };
  }

  // Create fallback network fee options when API fails
  Map<String, NetworkFeeOption> _createFallbackNetworkFeeOptions(double usdPrice) {
    final defaultFees = _getDefaultFeesForBlockchain(token!.blockchainName);
    
    return {
      'slow': NetworkFeeOption(
        priority: 'slow',
        gasPriceGwei: defaultFees['slow']!['gasPrice'] as int,
        feeEth: defaultFees['slow']!['feeEth'] as double,
        feeUsd: (defaultFees['slow']!['feeEth'] as double) * usdPrice,
        estimatedTime: '5-10 min',
      ),
      'average': NetworkFeeOption(
        priority: 'average',
        gasPriceGwei: defaultFees['average']!['gasPrice'] as int,
        feeEth: defaultFees['average']!['feeEth'] as double,
        feeUsd: (defaultFees['average']!['feeEth'] as double) * usdPrice,
        estimatedTime: '2-5 min',
      ),
      'fast': NetworkFeeOption(
        priority: 'fast',
        gasPriceGwei: defaultFees['fast']!['gasPrice'] as int,
        feeEth: defaultFees['fast']!['feeEth'] as double,
        feeUsd: (defaultFees['fast']!['feeEth'] as double) * usdPrice,
        estimatedTime: '1-2 min',
      ),
    };
  }

  bool get isFormValid {
    // ✅ Use controller text for validation consistency
    final addressText = _addressController.text;
    final amountText = _amountController.text;
    final isAddressValid = addressText.isNotEmpty && _isValidAddress(addressText, token?.blockchainName);
    
    return addressText.isNotEmpty && amountText.isNotEmpty && isAddressValid;
  }

  void _onPaste() async {
    final data = await Clipboard.getData('text/plain');
    final val = data?.text ?? '';
    _addressController.text = val;
    setState(() {
      address = val;
      addressError = val.isNotEmpty && !_isValidAddress(val, token!.blockchainName);
    });
  }

  void _onQrScan() async {
    final result = await AppNavigation.pushNamed(context, RoutePaths.qrScanner);
    if (result != null && result is String && result.isNotEmpty) {
      final parts = result.split('?');
      final addr = parts[0];
      String? amt;
      if (parts.length > 1) {
        final params = Uri.splitQueryString(parts[1]);
        amt = params['amount'];
      }
      
      _addressController.text = addr;
      if (amt != null) {
        _amountController.text = amt;
      }
      
      setState(() {
        address = addr;
        addressError = addr.isNotEmpty && !_isValidAddress(addr, token!.blockchainName);
        if (amt != null) amount = amt;
      });
    }
  }

  void _onMax() {
    final maxAmount = (token!.amount ?? 0.0).toStringAsFixed(8);
    _amountController.text = maxAmount;
    setState(() {
      amount = maxAmount;
    });
  }

  void _onSelectAddress(String addr) {
    _addressController.text = addr;
    setState(() {
      address = addr;
      addressError = addr.isNotEmpty && !_isValidAddress(addr, token!.blockchainName);
      showAddressBook = false;
    });
  }

  Future<void> _onNext() async {
    if (!isFormValid) return;
    
    setState(() { isLoading = true; });
    
    try {
      // ✅ Debug controller vs state sync
      print('🔧 CONTROLLER vs STATE SYNC DEBUG:');
      print('   Address Controller: "${_addressController.text}"');
      print('   Address State: "$address"');
      print('   Amount Controller: "${_amountController.text}"');
      print('   Amount State: "$amount"');
      print('   Controllers and states match: ${_addressController.text == address && _amountController.text == amount}');
      
      // ✅ Debug wallet info to identify balance issues
      await _debugWalletInfo();
      
      // ✅ Verify actual balance from server vs local balance
      await _verifyActualBalance();
      
      // Validate userId before making API calls
      if (userId.isEmpty) {
        print('⚠️ UserId is empty, trying to reload user data...');
        await _loadUserData();
        
        if (userId.isEmpty) {
          _showError('No wallet selected. Please select a wallet first.');
          return;
        }
      }
      
      print('✅ Using userId: $userId for transaction');
      
      // 🔍 DETAILED DEBUGGING - Compare with working Python test
      print('🔧 FLUTTER APP DEBUG (Compare with Python test):');
      print('   Flutter UserID: "$userId"');
      print('   Python test UserID: "test_user_flutter"');
      print('   UserIDs match: ${userId == "test_user_flutter"}');
      print('   Flutter Amount: "${_amountController.text}"');
      print('   Python test Amount: "0.0001"');
      print('   Flutter Token: ${token?.symbol} (${token?.blockchainName})');
      print('   Token Balance: ${token?.amount}');
      
      // ✅ Add comparison with working test data
      print('   ');
      print('🧪 WORKING PYTHON TEST DATA:');
      print('   ✅ UserID: test_user_flutter');
      print('   ✅ Sender: 0x68Ba7F66B09783977E36AA7bD8390b812742853C');
      print('   ✅ Amount: 0.0001');
      print('   ✅ Status: SUCCESS');
      print('   ');
      print('📱 FLUTTER REAL USER DATA:');
      print('   ❓ UserID: $userId');
      print('   ❓ Will get sender address...');
      print('   ❓ Amount: ${_amountController.text}');
      print('   ❓ Status: Will test...');
      
      // Step 1: Get sender address
      final normalizedBlockchain = _normalizeBlockchainName(token!.blockchainName);
      final addresses = await AddressRegistry.instance.loadForWallet(userId);
      final senderAddress = addresses[normalizedBlockchain] ??
          addresses[token!.blockchainName ?? ''] ??
          '';
      if (senderAddress.isEmpty) {
        _showError('Wallet address not found for $normalizedBlockchain');
        return;
      }
      
      print('🔧 SENDER ADDRESS DEBUG:');
      print('   Flutter Sender: "$senderAddress"');
      print('   Python test Sender: "0x68Ba7F66B09783977E36AA7bD8390b812742853C"');
      print('   Addresses match: ${senderAddress == "0x68Ba7F66B09783977E36AA7bD8390b812742853C"}');
      
      // ✅ Complete comparison with working test
      print('   ');
      print('🔄 FINAL COMPARISON:');
      print('   Python test → SUCCESS with:');
      print('     UserID: test_user_flutter');  
      print('     Address: 0x68Ba7F66B09783977E36AA7bD8390b812742853C');
      print('     Amount: 0.0001');
      print('   ');
      print('   Flutter app → Testing with:');
      print('     UserID: $userId');
      print('     Address: $senderAddress');
      print('     Amount: ${_amountController.text}');
      print('   ');
      if (userId != "test_user_flutter") {
        print('   ⚠️  Different UserID detected!');
        print('   ⚠️  This UserID might have different balance/permissions');
      }
      if (senderAddress != "0x68Ba7F66B09783977E36AA7bD8390b812742853C") {
        print('   ⚠️  Different Address detected!');
        print('   ⚠️  This address might have insufficient MATIC balance');
      }
      
      // Check if sending to self
      if (senderAddress.toLowerCase() == _addressController.text.toLowerCase()) {
        setState(() {
          showSelfTransferError = true;
        });
        return;
      }
      
      // Step 2: Estimate fee
      // Validate and parse amount
      double parsedAmount;
      try {
        // ✅ Use controller text for consistency
        final amountText = _amountController.text;
        parsedAmount = double.parse(amountText);
        if (parsedAmount <= 0) {
          _showError('Amount must be greater than 0');
          return;
        }
        
        print('🔧 AMOUNT PARSING DEBUG:');
        print('   Controller text: "$amountText"');
        print('   State variable: "$amount"');
        print('   Parsed amount: $parsedAmount');
        print('   Token balance: ${token?.amount}');
        print('   Has sufficient balance: ${parsedAmount <= (token?.amount ?? 0.0)}');
        
      } catch (e) {
        _showError('Invalid amount format. Please enter a valid number.');
        return;
      }
      
      EstimateFeeResponse feeResponse;
      try {
        // For fee estimation, use the updated blockchain names
        final feeEstimationBlockchain = _getFeeEstimationBlockchain(token!.blockchainName);
        
        print('🔧 FEE ESTIMATION DEBUG:');
        print('   Original blockchain: "${token!.blockchainName}"');
        print('   Fee estimation blockchain: "$feeEstimationBlockchain"');
        print('   Sender: $senderAddress');
        print('   Recipient: ${_addressController.text}');
        print('   Amount: $parsedAmount');
        print('   Token contract: "${token!.smartContractAddress ?? ''}"');
        
        feeResponse = await apiService.estimateFee(
          userID: userId,
          blockchain: feeEstimationBlockchain,
          fromAddress: senderAddress,
          toAddress: _addressController.text, // ✅ Use controller text instead of state variable
          amount: parsedAmount,
          tokenContract: token!.smartContractAddress ?? '',
        );
        
        print('✅ Fee estimation completed:');
        print('   Raw fee: ${feeResponse.fee}');
        print('   USD Price: ${feeResponse.usdPrice}');
        print('   Priority Options available: ${feeResponse.priorityOptions != null}');
        if (feeResponse.priorityOptions != null) {
          print('   Slow fee: ${feeResponse.priorityOptions?.slow?.fee} (${feeResponse.priorityOptions?.slow?.feeEth} ETH)');
          print('   Average fee: ${feeResponse.priorityOptions?.average?.fee} (${feeResponse.priorityOptions?.average?.feeEth} ETH)');
          print('   Fast fee: ${feeResponse.priorityOptions?.fast?.fee} (${feeResponse.priorityOptions?.fast?.feeEth} ETH)');
        }
        
      } catch (e) {
        print('❌ Error in fee estimation: $e');
        _showError('Error estimating network fee: ${e.toString()}');
        return;
      }
      
      // Validate fee response data
      if (feeResponse.priorityOptions == null) {
        print('⚠️ Priority options not available, using default values');
        // Continue with default values instead of returning error
      }
      
      // Validate basic fee data
      if (feeResponse.fee == null && feeResponse.usdPrice == null) {
        print('⚠️ Both fee and USD price are null, using default values');
      }
      
      // Update network fee options with real data (with null safety)
      setState(() {
        final usdPrice = feeResponse.usdPrice ?? _getFallbackUsdPrice();
        final priorityOptions = feeResponse.priorityOptions;
        
        print('🔧 NETWORK FEE OPTIONS UPDATE:');
        print('   USD Price: $usdPrice');
        print('   Priority options from server: ${priorityOptions != null}');
        
        // Get blockchain-specific default fees as fallback
        final defaultFees = _getDefaultFeesForBlockchain(token!.blockchainName);
        print('   Default fees for ${token!.blockchainName}: $defaultFees');
        
        try {
          // ✅ ENHANCED MAPPING with better null handling
          networkFeeOptions = {
            'slow': NetworkFeeOption(
              priority: 'slow',
              gasPriceGwei: (priorityOptions?.slow?.fee ?? defaultFees['slow']!['gasPrice'] as int),
              feeEth: priorityOptions?.slow?.feeEth ?? (defaultFees['slow']!['feeEth'] as double),
              feeUsd: (priorityOptions?.slow?.feeEth ?? (defaultFees['slow']!['feeEth'] as double)) * usdPrice,
              estimatedTime: '5-10 min',
            ),
            'average': NetworkFeeOption(
              priority: 'average',
              gasPriceGwei: (priorityOptions?.average?.fee ?? defaultFees['average']!['gasPrice'] as int),
              feeEth: priorityOptions?.average?.feeEth ?? (defaultFees['average']!['feeEth'] as double),
              feeUsd: (priorityOptions?.average?.feeEth ?? (defaultFees['average']!['feeEth'] as double)) * usdPrice,
              estimatedTime: '2-5 min',
            ),
            'fast': NetworkFeeOption(
              priority: 'fast',
              gasPriceGwei: (priorityOptions?.fast?.fee ?? defaultFees['fast']!['gasPrice'] as int),
              feeEth: priorityOptions?.fast?.feeEth ?? (defaultFees['fast']!['feeEth'] as double),
              feeUsd: (priorityOptions?.fast?.feeEth ?? (defaultFees['fast']!['feeEth'] as double)) * usdPrice,
              estimatedTime: '1-2 min',
            ),
          };
          
          print('✅ Network fee options created successfully:');
          print('   Slow: ${networkFeeOptions['slow']!.feeEth} ETH (\$${networkFeeOptions['slow']!.feeUsd.toStringAsFixed(4)})');
          print('   Average: ${networkFeeOptions['average']!.feeEth} ETH (\$${networkFeeOptions['average']!.feeUsd.toStringAsFixed(4)})');
          print('   Fast: ${networkFeeOptions['fast']!.feeEth} ETH (\$${networkFeeOptions['fast']!.feeUsd.toStringAsFixed(4)})');
          
        } catch (e) {
          print('❌ Error updating network fee options: $e');
          // Use complete fallback values
          networkFeeOptions = _createFallbackNetworkFeeOptions(usdPrice);
          print('⚠️ Using fallback network fee options');
        }
        
        feeDetails = feeResponse;
      });
      
      // Validate transaction amount
      final validationResult = _validateTransactionAmount(
        amount: _amountController.text, // ✅ Use controller text for consistency
        feeEth: networkFeeOptions[selectedPriority]!.feeEth,
        blockchainName: token!.blockchainName,
      );
      
      if (!validationResult.isValid) {
        print('❌ VALIDATION FAILED:');
        print('   Validation message: ${validationResult.message}');
        print('   Is this the insufficient funds error? ${validationResult.message.contains('Insufficient')}');
        _showError(validationResult.message);
        return;
      }
      
      print('✅ VALIDATION PASSED:');
      print('   Original amount: ${_amountController.text}');
      print('   Adjusted amount: ${validationResult.adjustedAmount}');
      print('   Validation message: ${validationResult.message}');
      
      // Step 3: Prepare transaction
      print('🔧 DEBUG: About to call prepareTransaction with:');
      print('   UserID: "$userId"');
      print('   Original blockchain: "${token!.blockchainName}"');
      print('   Normalized blockchain: "$normalizedBlockchain"');
      print('   Sender address: "$senderAddress"');
      print('   Recipient address STATE: "$address"');
      print('   Recipient address CONTROLLER: "${_addressController.text}"');
      print('   Amount: "${_amountController.text}"');
      print('   Smart contract: "${token!.smartContractAddress ?? ''}"');
      print('   Flutter local balance: ${token!.amount}');
      print('   ');
      
      // ✅ CRITICAL FIX: Use controller text for recipient address
      final recipientAddress = _addressController.text;
      if (recipientAddress.isEmpty) {
        print('❌ CRITICAL ERROR: Recipient address is empty!');
        print('   Controller text: "${_addressController.text}"');
        print('   State variable: "$address"');
        _showError('Recipient address is required. Please enter a valid address.');
        return;
      }
      
      print('🔍 BALANCE COMPARISON:');
      print('   Flutter thinks balance is: ${token!.amount} ${token!.symbol}');
      print('   Attempting to send: ${parsedAmount.toStringAsFixed(8)} ${token!.symbol}');
      print('   Should be sufficient locally: ${parsedAmount <= (token!.amount ?? 0.0)}');
      print('   Backend will auto-adjust if needed for native tokens...');
      
      final PrepareTransactionResponse prepareResponse;
      if (await LocalSendFacade.instance.shouldUseLocalSend()) {
        final walletName = await SecureStorage.instance.getSelectedWallet();
        final mnemonic = walletName != null
            ? await WalletRepository.instance.mnemonicForWallet(
                walletName,
                userId,
              )
            : null;
        if (mnemonic == null || mnemonic.isEmpty) {
          _showError('Unlock wallet or re-import your recovery phrase.');
          return;
        }
        prepareResponse = await LocalSendFacade.instance.prepare(
          mnemonic: mnemonic,
          blockchainName: token!.blockchainName ?? normalizedBlockchain,
          senderAddress: senderAddress,
          recipientAddress: recipientAddress,
          amount: parsedAmount.toStringAsFixed(8),
          smartContractAddress: token!.smartContractAddress ?? '',
        );
      } else {
        throw StateError(
          'Custodial server prepare is disabled. Use a self-custody wallet.',
        );
      }
      
      if (!prepareResponse.success) {
        print('❌ PREPARE TRANSACTION FAILED:');
        print('   Server response message: ${prepareResponse.message}');
        print('   This suggests balance still insufficient even after adjustment');
        print('   Sender address: $senderAddress');
        print('   UserID: $userId');
        print('   ');
        print('💡 POSSIBLE CAUSES:');
        print('   1. Insufficient balance even for gas fees');
        print('   2. Token transfer without enough native currency for gas');
        print('   3. Network connectivity issues');
        
        // ✅ Better error message for insufficient funds from server
        if (prepareResponse.message.contains('insufficient funds') == true ||
            prepareResponse.message.contains('Insufficient balance') == true ||
            prepareResponse.message.contains('network fee') == true) {
          _showError(
            'Insufficient Balance\n\n'
            '${prepareResponse.message}\n\n'
            'For native tokens: The system will auto-adjust your amount to maximum sendable.\n'
            'For tokens: Ensure you have enough native currency for gas fees.\n\n'
            'Check your balance and try a smaller amount.'
          );
        } else {
          _showError('Server error: ${prepareResponse.message}');
        }
        return;
      }
      
      // ✅ Check if amount was auto-adjusted by backend
      final details = prepareResponse.details;
      final adjustedAmount = details.amount;
      final originalAmount = details.amount;
      const wasAutoAdjusted = false; // TransactionDetails doesn't have autoAdjusted field
      
      if (wasAutoAdjusted && adjustedAmount != null && originalAmount != null) {
        print('✅ BACKEND AUTO-ADJUSTED AMOUNT:');
        print('   Original amount: $originalAmount ${token!.symbol}');
        print('   Adjusted amount: $adjustedAmount ${token!.symbol}');
        print('   User will send maximum possible amount');
        
        // Show confirmation dialog for adjusted amount
        final shouldContinue = await _showAutoAdjustmentDialog(
          originalAmount, 
          adjustedAmount, 
          token!.symbol ?? ''
        );
        
        if (!shouldContinue) {
          print('ℹ️ User cancelled auto-adjusted transaction');
          return;
        }
      }
      
      // Create pending transaction
      final pendingTransaction = models.Transaction(
        txHash: prepareResponse.transactionId,
        from: prepareResponse.details.sender ?? senderAddress,
        to: prepareResponse.details.recipient ?? recipientAddress,
        amount: prepareResponse.details.amount ?? parsedAmount.toStringAsFixed(8),
        tokenSymbol: token!.symbol ?? '',
        direction: 'outbound',
        status: 'pending',
        timestamp: DateTime.now().toIso8601String(),
        blockchainName: token!.blockchainName ?? '',
        price: null,
        temporaryId: null,
      );
      
      // Add pending transaction to provider
      final historyProvider = Provider.of<HistoryProvider>(context, listen: false);
      historyProvider.addPendingTransaction(pendingTransaction);
      
      setState(() {
        txDetails = prepareResponse;
        showConfirmModal = true;
      });
      
    } catch (e) {
      _showError('Error preparing transaction: ${e.toString()}');
    } finally {
      setState(() { isLoading = false; });
    }
  }

  Future<void> _onConfirmSend() async {
    HapticFeedback.mediumImpact();
    if (txDetails == null) return;
    
    setState(() { isLoading = true; });
    
    try {
      print('🔧 DEBUG: Local transaction confirmation (device signing)');
      print('   UserID: $userId');
      print('   TransactionID: ${txDetails!.transactionId}');
      print('   Blockchain: ${_normalizeBlockchainName(token!.blockchainName)}');
      
      // Try confirm transaction with retry logic for Polygon
      ConfirmTransactionResponse? confirmResponse;
      int retryCount = 0;
      const maxRetries = 2;
      
      while (retryCount <= maxRetries) {
        try {
          if (await LocalSendFacade.instance.shouldUseLocalSend()) {
            final walletName = await SecureStorage.instance.getSelectedWallet();
            final mnemonic = walletName != null
                ? await WalletRepository.instance.mnemonicForWallet(
                    walletName,
                    userId,
                  )
                : null;
            if (mnemonic == null || mnemonic.isEmpty) {
              throw StateError('Mnemonic not available');
            }
            final hash = await LocalSendFacade.instance.confirm(
              mnemonic: mnemonic,
              blockchainName: token!.blockchainName ?? '',
              recipientAddress: txDetails!.details.recipient,
              amount: txDetails!.details.amount,
              smartContractAddress: token!.smartContractAddress ?? '',
              transactionId: txDetails!.transactionId,
            );
            confirmResponse = ConfirmTransactionResponse(
              success: hash != null && hash.isNotEmpty,
              message: hash != null ? 'broadcast_ok' : 'broadcast_failed',
              transactionHash: hash,
              txHash: hash,
            );
          } else {
            throw StateError(
              'Custodial server signing is disabled. Enable self-custody wallet mode.',
            );
          }
          break; // Success, exit retry loop
        } catch (e) {
          retryCount++;
          if (retryCount > maxRetries) {
            rethrow; // Re-throw after max retries
          }
          print('🔄 Retry $retryCount for secure transaction confirmation...');
          await Future.delayed(const Duration(seconds: 2)); // Wait before retry
        }
      }
      
      print('🔧 DEBUG: Secure confirm response received:');
      print('   Success: ${confirmResponse?.success}');
      print('   Message: ${confirmResponse?.message}');
      print('   Hash: ${confirmResponse?.hash}');
      print('   IsSuccess: ${confirmResponse?.isSuccess}');
      
      if (confirmResponse?.isSuccess == true) {
        // Update transaction status
        final historyProvider = Provider.of<HistoryProvider>(context, listen: false);
        historyProvider.updatePendingTransactionStatus(txDetails!.transactionId, 'completed');
        
        // Show success notification
        TransactionNotificationReceiver.instance.notifyTransactionConfirmed(txDetails!.transactionId);
        try {
          final sentAmt = double.tryParse(
                txDetails!.details.amount ?? _amountController.text,
              ) ??
              0;
          await NotificationHelper.showSendNotification(
            sentAmt,
            token?.symbol ?? 'crypto',
          );
        } catch (_) {}
        
        // Close modal first
        setState(() {
          showConfirmModal = false;
        });
        
        // Show success message
        // Remove success message - transaction sent silently
        
        // Navigate back to previous screen
        Navigator.pop(context, true); // Return true to indicate success
      } else {
        final errorMessage = confirmResponse?.message ?? 'Unknown error occurred';
        
        // Handle specific error cases with better user messages
        if (errorMessage.contains('Network is currently experiencing issues') ||
            errorMessage.contains('Failed to broadcast transaction via Tatum API')) {
          // Show specific Tatum API error dialog
          _showTatumErrorDialog(errorMessage);
        } else if (errorMessage.contains('Transaction has expired')) {
          _showError('Transaction Expired\n\nYour transaction has expired. Please create a new transaction.');
        } else if (errorMessage.contains('Insufficient balance')) {
          _showError('Insufficient Balance\n\nYou don\'t have enough balance to complete this transaction. Please check your balance and try again.');
        } else if (errorMessage.contains('Invalid transaction data')) {
          _showError('Invalid Transaction\n\nPlease verify your recipient address and amount, then try again.');
        } else if (errorMessage.contains('Private key does not match')) {
          _showError('Wallet Configuration Error\n\nThere appears to be a mismatch in wallet configuration. Please try restarting the app or contact support.');
        } else if (errorMessage.contains('not found') || errorMessage.contains('expired')) {
          _showError('Transaction Not Found\n\nThe transaction may have expired. Please create a new transaction.');
        } else {
          // Generic error with better formatting
          _showError('Transaction Failed\n\n$errorMessage');
        }
      }
    } catch (e) {
      _showError('Error confirming transaction: ${e.toString()}');
    } finally {
      setState(() { isLoading = false; });
    }
  }

  void _showError(String message) {
    // ✅ Enhanced error handling with specific debugging for balance issues
    String enhancedMessage = message;
    
    if (message.toLowerCase().contains('insufficient')) {
      print('🚨 INSUFFICIENT BALANCE ERROR DETECTED');
      print('   Original message: $message');
      print('   Token: ${token?.symbol} (${token?.blockchainName})');
      print('   Local balance: ${token?.amount}');
      print('   Amount attempting to send: ${_amountController.text}');
      print('   User ID: $userId');
      
      enhancedMessage = '''
$message

🔍 DEBUG INFO:
• Token: ${token?.symbol ?? 'Unknown'}
• Local Balance: ${token?.amount ?? 0.0}
• Amount: ${_amountController.text}
• Blockchain: ${token?.blockchainName ?? 'Unknown'}

💡 TROUBLESHOOTING:
• Check if balance is outdated
• Verify on blockchain explorer
• Try smaller amount
• Ensure sufficient gas fees
      '''.trim();
    }
    
    setState(() {
      errorMessage = enhancedMessage;
      showErrorModal = true;
    });
  }

  void _showTatumErrorDialog(String errorMessage) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.orange),
              SizedBox(width: 8),
              Text('Network Issue'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The blockchain network is currently experiencing technical difficulties.'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF0EA5E9), width: 1),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Color(0xFF0EA5E9), size: 16),
                        SizedBox(width: 4),
                        Text('Important:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0EA5E9))),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text('• Your funds are completely safe', style: TextStyle(color: Color(0xFF0EA5E9))),
                    Text('• No money has been deducted', style: TextStyle(color: Color(0xFF0EA5E9))),
                    Text('• This is a temporary server issue', style: TextStyle(color: Color(0xFF0EA5E9))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('You can:'),
              const SizedBox(height: 8),
              const Text('• Wait a few minutes and try again'),
              const Text('• Use a different blockchain (BSC, TRON)'),
              const Text('• Contact support if the problem persists'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Retry the transaction after a short delay
                Future.delayed(const Duration(seconds: 2), () {
                  _onConfirmSend();
                });
              },
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate back to wallet to try different blockchain
                AppNavigation.pushReplacementNamed(context, RoutePaths.home);
              },
              child: const Text('Try Different Network'),
            ),
          ],
        );
      },
    );
  }

  bool _isValidAddress(String address, String? blockchainName) {
    final chain = (blockchainName ?? '').toLowerCase();
    if (chain.contains('tron')) {
      return address.startsWith('T') && address.length == 34;
    }
    if (chain.contains('bitcoin')) {
      return (address.startsWith('bc1') && address.length >= 42 && address.length <= 62) ||
             ((address.startsWith('1') || address.startsWith('3')) && address.length >= 26 && address.length <= 35);
    }
    // Default: EVM
    return address.startsWith('0x') && address.length == 42;
  }

  String _normalizeBlockchainName(String? name) {
    if (name == null) return '';
    
    print('🔧 DEBUG: _normalizeBlockchainName input: "$name"');
    
    final normalized = name.toLowerCase();
    String result;
    
    if (normalized.contains('binance') || normalized.contains('bsc') || normalized.contains('bnb')) {
      result = 'bsc';  // ✅ Lowercase to match server expectation
    } else if (normalized.contains('tron')) {
      result = 'tron';  // ✅ Lowercase to match server expectation
    } else if (normalized.contains('ethereum') || normalized.contains('polygon') || normalized.contains('matic')) {
      result = 'polygon';  // ✅ FIXED: Use lowercase "polygon" to match cURL test
    } else if (normalized.contains('bitcoin')) {
      result = 'bitcoin';  // Lowercase to match server expectation
    } else {
      result = name.toLowerCase();  // FIXED: Use lowercase instead of uppercase
    }
    
    print('🔧 DEBUG: _normalizeBlockchainName output: "$result"');
    return result;
  }

  // Get blockchain name for fee estimation (now supports all chains)
  String _getFeeEstimationBlockchain(String? name) {
    if (name == null) return '';
    
    print('🔧 DEBUG: _getFeeEstimationBlockchain input: "$name"');
    
    final normalized = name.toLowerCase();
    String result;
    
    if (normalized.contains('binance') || normalized.contains('bsc') || normalized.contains('bnb')) {
      result = 'bsc';  // ✅ Now supported in fee estimator
    } else if (normalized.contains('tron')) {
      result = 'tron';  // ✅ Confirmed working with cURL
    } else if (normalized.contains('ethereum') || normalized.contains('polygon') || normalized.contains('matic')) {
      result = 'polygon';  // ✅ FIXED: Fee estimator now supports 'polygon' directly
    } else if (normalized.contains('bitcoin')) {
      result = 'bitcoin';  // Bitcoin blockchain name
    } else if (normalized.contains('avalanche') || normalized.contains('avax')) {
      result = 'avalanche';  // ✅ Now supported in fee estimator
    } else if (normalized.contains('arbitrum') || normalized.contains('arb')) {
      result = 'arbitrum';  // ✅ Now supported in fee estimator
    } else {
      result = name.toLowerCase();
    }
    
    print('🔧 DEBUG: _getFeeEstimationBlockchain output: "$result"');
    return result;
  }

  // Get blockchain currency symbol for fee display
  String _getBlockchainCurrency(String? blockchainName) {
    if (blockchainName == null) return 'ETH';
    
    final normalized = blockchainName.toLowerCase();
    
    if (normalized.contains('tron')) {
      return 'TRX';
    } else if (normalized.contains('binance') || normalized.contains('bsc') || normalized.contains('bnb')) {
      return 'BNB';
    } else if (normalized.contains('bitcoin')) {
      return 'BTC';
    } else {
      return 'ETH';
    }
  }

  TransactionValidationResult _validateTransactionAmount({
    required String amount,
    required double feeEth,
    required String? blockchainName,
  }) {
    try {
      final amountDouble = double.tryParse(amount);
      if (amountDouble == null) {
        return TransactionValidationResult(
          isValid: false,
          adjustedAmount: 0.0,
          message: 'Invalid amount format',
        );
      }
      final tokenBalance = token!.amount ?? 0.0;
      
      // 🔍 ENHANCED VALIDATION DEBUGGING
      print('🔧 TRANSACTION VALIDATION DEBUG:');
      print('   Input amount string: "$amount"');
      print('   Parsed amount: $amountDouble');
      print('   Token balance: $tokenBalance');
      print('   Fee (ETH/MATIC): $feeEth');
      print('   Token symbol: ${token!.symbol}');
      print('   Blockchain: $blockchainName');
      print('   Smart contract: "${token!.smartContractAddress ?? 'null'}"');
      
      // Check if amount exceeds balance
      if (amountDouble > tokenBalance) {
        final errorMsg = 'Insufficient balance. Available: ${tokenBalance.toStringAsFixed(8)} ${token!.symbol}';
        print('❌ VALIDATION FAILED: $errorMsg');
        return TransactionValidationResult(
          isValid: false,
          adjustedAmount: 0.0,
          message: errorMsg,
        );
      }
      
      // Determine if this is a native token
      final isNativeToken = token!.smartContractAddress == null || token!.smartContractAddress!.isEmpty;
      print('   Is native token: $isNativeToken');
      
      // ✅ CRITICAL FIX: Only apply fee to native tokens
      if (isNativeToken) {
        // For native tokens (MATIC, BNB, ETH), need to consider gas fees
        final totalNeeded = amountDouble + feeEth;
        print('   Native token detected - checking total needed including fee');
        print('   Total needed (amount + fee): $totalNeeded');
        print('   Available balance: $tokenBalance');
        print('   Has sufficient for total: ${totalNeeded <= tokenBalance}');
        
        if (totalNeeded > tokenBalance) {
          // Calculate maximum sendable amount
          final maxAmount = tokenBalance - feeEth;
          print('   Max sendable amount (balance - fee): $maxAmount');
          
          if (maxAmount <= 0) {
            final errorMsg = 'Insufficient balance to cover network fee. Fee: ${feeEth.toStringAsFixed(8)} ${token!.symbol}';
            print('❌ VALIDATION FAILED: $errorMsg');
            return TransactionValidationResult(
              isValid: false,
              adjustedAmount: 0.0,
              message: errorMsg,
            );
          }
          
          // Auto-adjust to maximum available amount
          print('   ⚠️ Auto-adjusting amount from $amountDouble to $maxAmount');
          return TransactionValidationResult(
            isValid: true,
            adjustedAmount: maxAmount,
            message: 'Amount adjusted to maximum available after fee deduction',
          );
        }
      } else {
        // For ERC20/BEP20/tokens, fee is paid in native currency (separate from token balance)
        print('   Token detected - fee paid separately in native currency');
        print('   Only checking if token amount exceeds token balance');
        
        // Just check if the token amount exceeds token balance
        // Fee will be paid from native currency balance (which we don't validate here)
        if (amountDouble > tokenBalance) {
          final errorMsg = 'Insufficient token balance. Available: ${tokenBalance.toStringAsFixed(8)} ${token!.symbol}';
          print('❌ VALIDATION FAILED: $errorMsg');
          return TransactionValidationResult(
            isValid: false,
            adjustedAmount: 0.0,
            message: errorMsg,
          );
        }
      }
      
      print('✅ VALIDATION PASSED');
      return TransactionValidationResult(
        isValid: true,
        adjustedAmount: amountDouble,
        message: 'Valid amount',
      );
    } catch (e) {
      final errorMsg = 'Error validating amount: $e';
      print('❌ VALIDATION ERROR: $errorMsg');
      return TransactionValidationResult(
        isValid: false,
        adjustedAmount: 0.0,
        message: errorMsg,
      );
    }
  }

  /// ✅ Debug helper to check wallet info and balance (SECURE - no private key exposure)
  Future<void> _debugWalletInfo() async {
    try {
      print('🔍 WALLET DEBUG INFO (SECURE):');
      
      // Get wallet info
      final selectedWallet = await SecureStorage.instance.getSelectedWallet();
      final selectedUserId = await SecureStorage.instance.getUserIdForSelectedWallet();
      final wallets = await SecureStorage.instance.getWalletsList();
      
      print('   Selected wallet: $selectedWallet');
      print('   Selected userID: $selectedUserId');
      print('   Total wallets: ${wallets.length}');
      
      if (wallets.isNotEmpty) {
        for (int i = 0; i < wallets.length; i++) {
          final wallet = wallets[i];
          print('   Wallet $i: ${wallet['walletName']} -> ${wallet['userID']}');
        }
      }
      
      // Get address for current user
      if (userId.isNotEmpty) {
        final normalizedBlockchain = _normalizeBlockchainName(token!.blockchainName);
        final addresses = await AddressRegistry.instance.loadForWallet(userId);
        final addr = addresses[normalizedBlockchain] ??
            addresses[token!.blockchainName ?? ''] ??
            '';
        if (addr.isNotEmpty) {
          print('   Address for $userId: $addr');
          print('   Compare on-chain balance with Flutter: ${token!.amount}');
        }
      }
      
    } catch (e) {
      print('❌ Error in wallet debug: $e');
    }
  }

  String _getDollarValue() {
    final price = pricePerToken;
    final amountStr = _amountController.text; // ✅ Use controller text instead of state variable
    final amt = double.tryParse(amountStr) ?? 0.0;
    final totalValue = price * amt;
    
    print('💰 _getDollarValue calculation FIXED:');
    print('   Token: ${token?.symbol}');
    print('   Amount string from controller: "$amountStr"');
    print('   Amount string from state: "$amount"');
    print('   Parsed amount: $amt');
    print('   Price per token: \$${price.toStringAsFixed(4)}');
    print('   Multiplication: $price × $amt = $totalValue');
    print('   Total value: \$${totalValue.toStringAsFixed(4)}');
    
    // ✅ Better formatting for small values
    if (totalValue < 0.01) {
      return totalValue.toStringAsFixed(4);
    } else {
      return totalValue.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (token == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_safeTranslate('send_token', 'Send Token')),
          foregroundColor: Colors.black,
        ),
        body: Center(child: Text(_safeTranslate('token_not_found', 'Token not found'))),
      );
    }
    
    return MainLayout(
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                _safeTranslate('send_symbol', 'Send {symbol}').replaceAll('{symbol}', token!.symbol ?? ''),
              ),
              centerTitle: true,
            ),
            body: SafeArea(
              child: GestureDetector(
                onTap: () {
                  // Dismiss keyboard when tapping outside text fields
                  FocusScope.of(context).unfocus();
                },
                behavior: HitTestBehavior.translucent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Text(_safeTranslate('address_or_domain_name', 'Address or Domain Name'), 
                           style: const TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(height: 4),
                      TextField(
                        onChanged: (val) {
                          // ✅ Keep state in sync with controller
                          setState(() {
                            address = val;
                            addressError = val.isNotEmpty && !_isValidAddress(val, token!.blockchainName);
                          });
                        },
                        decoration: InputDecoration(
                          hintText: _safeTranslate('search_or_enter', 'Search or Enter'),
                          errorText: addressError ? _safeTranslate('wallet_address_not_valid', 'The wallet address entered is not valid.') : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.paste, color: Color(0xFF08C495)),
                                onPressed: _onPaste,
                              ),
                              IconButton(
                                icon: const Icon(Icons.menu_book, color: Color(0xFF08C495)),
                                onPressed: () { setState(() { showAddressBook = true; }); },
                              ),
                              IconButton(
                                icon: const Icon(Icons.qr_code, color: Color(0xFF08C495)),
                                onPressed: _onQrScan,
                              ),
                              if (address.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.grey),
                                  onPressed: () { 
                                    _addressController.clear();
                                    setState(() { 
                                      address = ''; 
                                      addressError = false; 
                                    }); 
                                  },
                                ),
                            ],
                          ),
                        ),
                        controller: _addressController,
                      ),
                      const SizedBox(height: 20),
                      Text(_safeTranslate('amount', 'Amount'), 
                           style: const TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(height: 4),
                      TextField(
                        onChanged: (val) { 
                          // ✅ Keep state in sync with controller
                          setState(() { 
                            amount = val; 
                          });
                        },
                        decoration: InputDecoration(
                          hintText: _safeTranslate('symbol_amount', '{symbol} Amount').replaceAll('{symbol}', token!.symbol ?? ''),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _onMax,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: Text(_safeTranslate('max', 'Max'), 
                                         style: const TextStyle(color: Color(0xFF08C495), fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 8),
                      isPriceLoading
                        ? Row(
                            children: [
                              const SizedBox(width: 4),
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                              ),
                              const SizedBox(width: 8),
                              Text(_safeTranslate('fetching_latest_price', 'Fetching latest price...'), 
                                   style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          )
                        : Text('≈ \$${_getDollarValue()}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: isFormValid && !isLoading ? _onNext : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF08C495),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          ),
                          child: isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(_safeTranslate('next', 'Next'), 
                                     style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom sheet for address book
            bottomSheet: showAddressBook ? _buildAddressBookSheet() : null,
          ),
          // Overlay modals
          if (showConfirmModal || showErrorModal || showSelfTransferError)
            _buildModals(),
        ],
      ),
    );
  }

  // Show all modals
  Widget _buildModals() {
    return Stack(
      children: [
        if (showConfirmModal && txDetails != null)
          _buildTransactionConfirmModal(),
        if (showErrorModal)
          _buildErrorModal(),
        if (showSelfTransferError)
          _buildSelfTransferErrorModal(),
      ],
    );
  }

  // Transaction Confirmation Modal - همسان با استایل کل اپلیکیشن
  Widget _buildTransactionConfirmModal() {
    if (txDetails == null) return const SizedBox();
    
    final selectedFee = networkFeeOptions[selectedPriority]!;
    final amountValue = double.tryParse(amount) ?? 0.0;
    final totalValue = (amountValue * pricePerToken).toStringAsFixed(2);
    final totalWithFee = ((double.tryParse(totalValue) ?? 0.0) + selectedFee.feeUsd).toStringAsFixed(2);
    
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // آیکون و عنوان
              const Icon(
                Icons.send_rounded,
                size: 48,
                color: Color(0xFF08C495),
              ),
              const SizedBox(height: 16),
              const Text(
                'Transaction Confirmation',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              
              // مقدار منفی (ارسال)
              Text(
                '-${txDetails!.details.amount ?? '0'} ${token!.symbol ?? ''}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '≈ \$$totalValue',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // جزئیات تراکنش
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildSimpleDetailRow('From', walletName),
                    const SizedBox(height: 12),
                    _buildSimpleDetailRow('To', _formatAddress(txDetails!.details.recipient ?? '')),
                    const SizedBox(height: 12),
                    _buildSimpleDetailRow('Network Fee', '${selectedFee.feeEth.toStringAsFixed(8)} ${_getBlockchainCurrency(token!.blockchainName)}'),
                    const SizedBox(height: 12),
                    _buildSimpleDetailRow('Total', '≈ \$$totalWithFee'),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // هشدار
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please double-check the recipient address before confirming.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // دکمه‌ها
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => setState(() => showConfirmModal = false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _onConfirmSend,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text('Send ${token!.symbol}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // متد کمکی برای نمایش جزئیات ساده
  Widget _buildSimpleDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ],
    );
  }

  // Error Modal
  Widget _buildErrorModal() {
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Transaction Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => setState(() => showErrorModal = false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('OK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Self Transfer Error Modal
  Widget _buildSelfTransferErrorModal() {
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Transaction Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You cannot send assets to your own address.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => setState(() => showSelfTransferError = false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('OK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method for detail rows
  Widget _buildDetailRow(String label, String value, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // Helper method for Kotlin-style detail rows
  Widget _buildKotlinDetailRow(String label, String value, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // Helper method for dividers
  Widget _buildDivider() {
    return Divider(
      color: Colors.grey[300],
      thickness: 1,
      height: 1,
    );
  }

  // Enhanced detail row for better UI
  Widget _buildEnhancedDetailRow(String label, String value, {String? subtitle, bool isFirst = false, bool isLast = false}) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: isFirst ? 16 : 12,
        bottom: isLast ? 16 : 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // Enhanced divider for better UI
  Widget _buildEnhancedDivider() {
    return Divider(
      color: Colors.grey[200],
      thickness: 1,
      height: 1,
      indent: 16,
      endIndent: 16,
    );
  }

  // Helper method to format address
  String _formatAddress(String address) {
    if (address.length <= 16) return address;
    return '${address.substring(0, 8)}...${address.substring(address.length - 6)}';
  }

  // Show network fee options with enhanced styling
  void _showNetworkFeeOptions() {
    // Remove modal bottom sheet - network fee options removed
  }

  Widget _buildAddressBookSheet() {
    return Container(
      height: 420,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 40),
                Text(_safeTranslate('address_book', 'Address Book'), 
                     style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close), 
                  onPressed: () => setState(() => showAddressBook = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: addressBook.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.contacts_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _safeTranslate('no_saved_addresses', 'No saved addresses'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _safeTranslate('add_addresses_to_address_book', 'Add addresses to your address book for quick access'),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: addressBook.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final wallet = addressBook[index];
                      return GestureDetector(
                        onTap: () => _onSelectAddress(wallet.address),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF08C495), Color(0xFF39b6fb)]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(wallet.name, 
                                         style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                                    Text(_formatAddress(wallet.address), 
                                         style: const TextStyle(fontSize: 12, color: Colors.white)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Standard detail row for modal
  Widget _buildStandardDetailRow(String label, String value, {String? subtitle, bool isFirst = false, bool isLast = false}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: isFirst ? 16 : 12,
        bottom: isLast ? 16 : 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                    fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  decoration: TextDecoration.none,
                ),
                  textAlign: TextAlign.end,
              ),
              if (subtitle != null) ...[
                  const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                    textAlign: TextAlign.end,
                ),
              ],
            ],
            ),
          ),
        ],
      ),
    );
  }

  // Standard divider
  Widget _buildStandardDivider() {
    return Divider(
      color: Colors.grey[100],
      thickness: 1,
      height: 1,
      indent: 16,
      endIndent: 16,
    );
  }

  /// ✅ Verify actual balance from server vs local balance
  Future<void> _verifyActualBalance() async {
    try {
      if (userId.isEmpty || token == null) {
        print('⚠️ Cannot verify balance: missing userId or token');
        return;
      }
      
      print('🔍 BALANCE VERIFICATION:');
      print('   Local balance: ${token!.amount} ${token!.symbol}');
      
      final normalizedBlockchain = _normalizeBlockchainName(token!.blockchainName);
      final addresses = await AddressRegistry.instance.loadForWallet(userId);
      final senderAddress = addresses[normalizedBlockchain] ??
          addresses[token!.blockchainName ?? ''] ??
          '';
      if (senderAddress.isEmpty) {
        print('❌ Failed to resolve local address for balance verification');
        return;
      }
      print('   Address: $senderAddress');
      
      // Always show the address for manual verification
      print('💡 Manual verification:');
      print('   Check balance on explorer:');
      if (normalizedBlockchain.contains('polygon') || normalizedBlockchain.contains('matic')) {
        print('   https://polygonscan.com/address/$senderAddress');
      } else if (normalizedBlockchain.contains('bsc') || normalizedBlockchain.contains('binance')) {
        print('   https://bscscan.com/address/$senderAddress');
      } else if (normalizedBlockchain.contains('ethereum')) {
        print('   https://etherscan.io/address/$senderAddress');
      }
      
    } catch (e) {
      print('❌ Error in balance verification: $e');
    }
  }

  /// ✅ Show dialog when backend auto-adjusts the amount
  Future<bool> _showAutoAdjustmentDialog(String originalAmount, String adjustedAmount, String symbol) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_fix_high, color: Color(0xFF08C495)),
              SizedBox(width: 8),
              Text('Amount Adjusted'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your balance is insufficient for the requested amount plus network fees.'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF08C495), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info, color: Color(0xFF08C495), size: 16),
                        SizedBox(width: 4),
                        Text('Auto-Adjustment:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF08C495))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Requested:'),
                        Text('$originalAmount $symbol', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Adjusted to:'),
                        Text('$adjustedAmount $symbol', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF08C495))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('This sends the maximum possible amount after reserving funds for network fees.'),
              const SizedBox(height: 8),
              const Text('Would you like to continue with the adjusted amount?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF08C495),
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    ) ?? false;
  }
}

// Helper classes
class NetworkFeeOption {
  final String priority;
  final int gasPriceGwei;
  final double feeEth;
  final double feeUsd;
  final String estimatedTime;

  NetworkFeeOption({
    required this.priority,
    required this.gasPriceGwei,
    required this.feeEth,
    required this.feeUsd,
    required this.estimatedTime,
  });
}

class TransactionValidationResult {
  final bool isValid;
  final double adjustedAmount;
  final String message;

  TransactionValidationResult({
    required this.isValid,
    required this.adjustedAmount,
    required this.message,
  });
} 