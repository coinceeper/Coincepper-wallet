import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/crypto_token.dart';
import '../../models/address_book_entry.dart';
import '../../models/network_fee_option.dart';
import '../../services/secure_storage.dart';
import '../../services/api_models.dart';
import '../../wallet/transactions/local_send_facade.dart';
import '../../wallet/address_registry.dart';
import '../../domain/services/fee_estimation_service.dart';
import '../../domain/services/address_validation_service.dart';
import '../../domain/services/send_transaction_service.dart';
import '../../providers/history_provider.dart';
import '../../providers/token_provider.dart';
import '../../providers/price_provider.dart';
import '../../di/service_locator.dart';
import '../../utils/secure_log.dart';

/// Represents the current step in the send flow UI.
enum SendFlowStep { form, confirm, error, selfTransferError }

/// UI state for the send detail screen.
///
/// This ViewModel encapsulates ALL state management and business logic
/// for the send transaction flow, keeping the UI layer pure and testable.
class SendDetailViewModel extends ChangeNotifier {
  // ==================== TOKEN DATA ====================
  CryptoToken? _token;
  CryptoToken? get token => _token;

  // ==================== TEXT CONTROLLERS ====================
  final addressController = TextEditingController();
  final amountController = TextEditingController();

  // ==================== FORM STATE ====================
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isPriceLoading = false;
  bool get isPriceLoading => _isPriceLoading;

  bool _addressError = false;
  bool get addressError => _addressError;

  double _pricePerToken = 0.0;
  double get pricePerToken => _pricePerToken;

  String _walletName = 'My Wallet';
  String get walletName => _walletName;

  String _userId = '';
  String get userId => _userId;

  // ==================== FLOW STATE ====================
  SendFlowStep _currentStep = SendFlowStep.form;
  SendFlowStep get currentStep => _currentStep;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  // ==================== TRANSACTION STATE ====================
  PrepareTransactionResponse? _txDetails;
  PrepareTransactionResponse? get txDetails => _txDetails;

  String? _selectedPriority = 'average';
  String? get selectedPriority => _selectedPriority;

  Map<String, NetworkFeeOption> _networkFeeOptions = {};
  Map<String, NetworkFeeOption> get networkFeeOptions => _networkFeeOptions;

  // ==================== ADDRESS BOOK ====================
  bool _showAddressBook = false;
  bool get showAddressBook => _showAddressBook;

  List<AddressBookEntry> _addressBook = [];
  List<AddressBookEntry> get addressBook => _addressBook;

  // ==================== SERVICES ====================
  final FeeEstimationService _feeService = ServiceLocator.get<FeeEstimationService>();
  final AddressValidationService _addressValidation = ServiceLocator.get<AddressValidationService>();
  final SendTransactionService _sendTransactionService = ServiceLocator.get<SendTransactionService>();

  // ==================== INITIALIZATION ====================

  /// Initialize the ViewModel with token data from JSON.
  Future<void> initialize(String tokenJson, BuildContext context) async {
    _parseToken(tokenJson);
    await _loadUserData();
    await _loadAddressBook();
    await _fetchPrice(context);
  }

  void _parseToken(String tokenJson) {
    try {
      final decodedJson = Uri.decodeComponent(tokenJson);
      final tokenData = jsonDecode(decodedJson) as Map<String, dynamic>;
      _token = CryptoToken.fromJson(tokenData);
      notifyListeners();
    } catch (e) {
      _token = null;
      notifyListeners();
    }
  }

  Future<void> _loadUserData() async {
    try {
      final selectedWallet = await ServiceLocator.get<SecureStorage>().getSelectedWallet();
      final selectedUserId = await ServiceLocator.get<SecureStorage>().getUserIdForSelectedWallet();

      if (selectedWallet != null && selectedUserId != null) {
        _walletName = selectedWallet;
        _userId = selectedUserId;
        return;
      }

      final wallets = await ServiceLocator.get<SecureStorage>().getWalletsList();
      if (wallets.isNotEmpty) {
        final firstWallet = wallets.first;
        final firstWalletName = firstWallet['walletName'];
        final firstWalletUserId = firstWallet['userID'];

        if (firstWalletName != null && firstWalletUserId != null) {
          _walletName = firstWalletName;
          _userId = firstWalletUserId;
          await ServiceLocator.get<SecureStorage>().saveSelectedWallet(firstWalletName, firstWalletUserId);
        }
      }
    } catch (e) {
      SecureLog.w('Error loading wallet info in SendDetail', error: e);
    }
  }

  Future<void> _loadAddressBook() async {
    _addressBook = await _addressValidation.loadAddressBook();
    notifyListeners();
  }

  Future<void> _fetchPrice(BuildContext context) async {
    _isPriceLoading = true;
    notifyListeners();

    try {
      if (_token?.symbol == null) {
        _pricePerToken = 0.0;
        _isPriceLoading = false;
        notifyListeners();
        return;
      }

      final tokenSymbol = _token!.symbol!;
      double? price;

      try {
        final tokenProvider = Provider.of<TokenProvider>(context, listen: false);
        price = tokenProvider.getTokenPrice(tokenSymbol, 'USD');
      } catch (e) {
        SecureLog.w('SendDetailVM: failed to get token price from provider', error: e);
        price = null;
      }

      if (price == null || price == 0.0) {
        try {
          final priceProvider = Provider.of<PriceProvider>(context, listen: false);
          await priceProvider.fetchPrices([tokenSymbol], currencies: ['USD']);
          price = priceProvider.getPrice(tokenSymbol);
        } catch (e) {
          SecureLog.w('SendDetailVM: failed to fetch price from API', error: e);
          price = null;
        }
      }

      _pricePerToken = price ?? 0.0;
    } catch (e) {
      SecureLog.w('SendDetailVM: price resolution failed, using zero', error: e);
      _pricePerToken = 0.0;
    }

    _isPriceLoading = false;
    notifyListeners();
  }

  // ==================== FORM VALIDATION ====================

  bool get isFormValid {
    final addressText = addressController.text;
    final amountText = amountController.text;
    final isAddressValid = addressText.isNotEmpty && isValidAddress(addressText);
    return addressText.isNotEmpty && amountText.isNotEmpty && isAddressValid;
  }

  bool isValidAddress(String address) {
    return _addressValidation.isValidAddress(address, _token?.blockchainName);
  }

  // ==================== INPUT HANDLERS ====================

  void onAddressChanged(String val) {
    _addressError = val.isNotEmpty && !isValidAddress(val);
    notifyListeners();
  }

  void onAmountChanged(String val) {
    notifyListeners();
  }

  Future<void> onPaste() async {
    final data = await Clipboard.getData('text/plain');
    final val = data?.text ?? '';
    addressController.text = val;
    onAddressChanged(val);
  }

  void onQrScanResult(String? result) {
    if (result == null || result.isEmpty) return;

    final parts = result.split('?');
    final addr = parts[0];
    String? amt;
    if (parts.length > 1) {
      final params = Uri.splitQueryString(parts[1]);
      amt = params['amount'];
    }

    addressController.text = addr;
    _addressError = addr.isNotEmpty && !isValidAddress(addr);
    if (amt != null) {
      amountController.text = amt;
    }
    notifyListeners();
  }

  void onMax() {
    final maxAmount = (_token?.amount ?? 0.0).toStringAsFixed(8);
    amountController.text = maxAmount;
    notifyListeners();
  }

  void onClearAddress() {
    addressController.clear();
    _addressError = false;
    notifyListeners();
  }

  // ==================== ADDRESS BOOK ====================

  void toggleAddressBook() {
    _showAddressBook = !_showAddressBook;
    notifyListeners();
  }

  void onSelectAddress(String addr) {
    addressController.text = addr;
    _addressError = addr.isNotEmpty && !isValidAddress(addr);
    _showAddressBook = false;
    notifyListeners();
  }

  // ==================== FEE OPTIONS ====================

  void setSelectedPriority(String priority) {
    _selectedPriority = priority;
    notifyListeners();
  }

  Map<String, NetworkFeeOption> _createFallbackNetworkFeeOptions(double usdPrice) {
    final defaultFees = _feeService.getDefaultFeesForBlockchain(_token!.blockchainName);

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

  // ==================== TRANSACTION FLOW ====================

  /// Prepare the transaction. Returns true if preparation succeeded.
  Future<bool> onNext(BuildContext context) async {
    if (!isFormValid) return false;

    _isLoading = true;
    notifyListeners();

    try {
      if (_userId.isEmpty) {
        await _loadUserData();
        if (_userId.isEmpty) {
          _showError('No wallet selected. Please select a wallet first.');
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }

      final NormalizedAndAddress? normalizedResult = await _getSenderAddress();
      if (normalizedResult == null) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final senderAddress = normalizedResult.address;
      final normalizedBlockchain = normalizedResult.normalizedName;

      // Check self-transfer
      if (senderAddress.toLowerCase() == addressController.text.toLowerCase()) {
        _currentStep = SendFlowStep.selfTransferError;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Parse amount
      double parsedAmount;
      try {
        parsedAmount = double.parse(amountController.text);
        if (parsedAmount <= 0) {
          _showError('Amount must be greater than 0');
          _isLoading = false;
          notifyListeners();
          return false;
        }
      } catch (e) {
        _showError('Invalid amount format. Please enter a valid number.');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Estimate fee
      final feeResponse = await _estimateFee(
        context: context,
        normalizedBlockchain: normalizedBlockchain,
        senderAddress: senderAddress,
        parsedAmount: parsedAmount,
      );
      if (feeResponse == null) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Update fee options
      _updateNetworkFeeOptions(feeResponse);

      // Validate amount
      final validationResult = _sendTransactionService.validateTransactionAmount(
        amount: amountController.text,
        feeEth: _networkFeeOptions[_selectedPriority]!.feeEth,
        tokenBalance: _token!.amount,
        smartContractAddress: _token!.smartContractAddress,
        tokenSymbol: _token!.symbol ?? '',
        blockchainName: _token!.blockchainName,
      );

      if (!validationResult.isValid) {
        _showError(validationResult.message);
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Prepare transaction
      final recipientAddress = addressController.text;
      if (recipientAddress.isEmpty) {
        _showError('Recipient address is required. Please enter a valid address.');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final prepareResponse = await _prepareTransaction(
        context: context,
        normalizedBlockchain: normalizedBlockchain,
        senderAddress: senderAddress,
        recipientAddress: recipientAddress,
        parsedAmount: parsedAmount,
      );
      if (prepareResponse == null) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Create pending transaction
      _addPendingTransaction(context, prepareResponse, senderAddress, recipientAddress, parsedAmount);

      _txDetails = prepareResponse;
      _currentStep = SendFlowStep.confirm;
    } catch (e) {
      _showError('Error preparing transaction: ${e.toString()}');
    }

    _isLoading = false;
    notifyListeners();
    return true;
  }

  Future<NormalizedAndAddress?> _getSenderAddress() async {
    final normalizedBlockchain = _feeService.normalizeBlockchainName(_token!.blockchainName);
    final addresses = await ServiceLocator.get<AddressRegistry>().loadForWallet(_userId);
    final senderAddress = addresses[normalizedBlockchain] ?? addresses[_token!.blockchainName ?? ''] ?? '';
    if (senderAddress.isEmpty) {
      _showError('Wallet address not found for $normalizedBlockchain');
      return null;
    }
    return NormalizedAndAddress(address: senderAddress, normalizedName: normalizedBlockchain);
  }

  Future<Map<String, dynamic>?> _estimateFee({
    required BuildContext context,
    required String normalizedBlockchain,
    required String senderAddress,
    required double parsedAmount,
  }) async {
    try {
      final feeEstimationBlockchain = _feeService.getFeeEstimationBlockchain(_token!.blockchainName);
      final feeResponse = await _feeService.estimateFee(
        blockchainName: feeEstimationBlockchain,
        fromAddress: senderAddress,
        toAddress: addressController.text,
        amount: parsedAmount,
        tokenContract: _token!.smartContractAddress ?? '',
      );
      return feeResponse;
    } catch (e) {
      _showError('Error estimating network fee: ${e.toString()}');
      return null;
    }
  }

  void _updateNetworkFeeOptions(Map<String, dynamic> feeResponse) {
    final usdPrice = (feeResponse['usd_price'] as num?)?.toDouble() ?? _pricePerToken;
    final priorityOptionsRaw = feeResponse['priority_options'] as Map<String, dynamic>?;
    final defaultFees = _feeService.getDefaultFeesForBlockchain(_token!.blockchainName);

    try {
      _networkFeeOptions = {
        'slow': NetworkFeeOption(
          priority: 'slow',
          gasPriceGwei: (priorityOptionsRaw?['slow']?['fee'] as int? ?? defaultFees['slow']!['gasPrice'] as int),
          feeEth: (priorityOptionsRaw?['slow']?['feeEth'] as num?)?.toDouble() ?? (defaultFees['slow']!['feeEth'] as double),
          feeUsd: ((priorityOptionsRaw?['slow']?['feeEth'] as num?)?.toDouble() ?? (defaultFees['slow']!['feeEth'] as double)) * usdPrice,
          estimatedTime: '5-10 min',
        ),
        'average': NetworkFeeOption(
          priority: 'average',
          gasPriceGwei: (priorityOptionsRaw?['average']?['fee'] as int? ?? defaultFees['average']!['gasPrice'] as int),
          feeEth: (priorityOptionsRaw?['average']?['feeEth'] as num?)?.toDouble() ?? (defaultFees['average']!['feeEth'] as double),
          feeUsd: ((priorityOptionsRaw?['average']?['feeEth'] as num?)?.toDouble() ?? (defaultFees['average']!['feeEth'] as double)) * usdPrice,
          estimatedTime: '2-5 min',
        ),
        'fast': NetworkFeeOption(
          priority: 'fast',
          gasPriceGwei: (priorityOptionsRaw?['fast']?['fee'] as int? ?? defaultFees['fast']!['gasPrice'] as int),
          feeEth: (priorityOptionsRaw?['fast']?['feeEth'] as num?)?.toDouble() ?? (defaultFees['fast']!['feeEth'] as double),
          feeUsd: ((priorityOptionsRaw?['fast']?['feeEth'] as num?)?.toDouble() ?? (defaultFees['fast']!['feeEth'] as double)) * usdPrice,
          estimatedTime: '1-2 min',
        ),
      };
    } catch (e) {
      SecureLog.w('SendDetailVM: failed to build network fee options, using fallback', error: e);
      _networkFeeOptions = _createFallbackNetworkFeeOptions(usdPrice);
    }
  }

  Future<PrepareTransactionResponse?> _prepareTransaction({
    required BuildContext context,
    required String normalizedBlockchain,
    required String senderAddress,
    required String recipientAddress,
    required double parsedAmount,
  }) async {
    try {
      if (!await ServiceLocator.get<LocalSendFacade>().shouldUseLocalSend()) {
        throw StateError('Custodial server prepare is disabled. Use a self-custody wallet.');
      }

      final prepareResponse = await _sendTransactionService.prepareTransaction(
        userId: _userId,
        blockchainName: _token!.blockchainName ?? normalizedBlockchain,
        senderAddress: senderAddress,
        recipientAddress: recipientAddress,
        amount: parsedAmount.toStringAsFixed(8),
        smartContractAddress: _token!.smartContractAddress ?? '',
      );

      if (!prepareResponse.success) {
        if (prepareResponse.message.contains('insufficient funds') ||
            prepareResponse.message.contains('Insufficient balance') ||
            prepareResponse.message.contains('network fee')) {
          _showError(
            'Insufficient Balance\n\n'
            '${prepareResponse.message}\n\n'
            'For native tokens: The system will auto-adjust your amount to maximum sendable.\n'
            'For tokens: Ensure you have enough native currency for gas fees.\n\n'
            'Check your balance and try a smaller amount.',
          );
        } else {
          _showError('Server error: ${prepareResponse.message}');
        }
        return null;
      }

      return prepareResponse;
    } catch (e) {
      _showError('Error preparing transaction: ${e.toString()}');
      return null;
    }
  }

  void _addPendingTransaction(
    BuildContext context,
    PrepareTransactionResponse prepareResponse,
    String senderAddress,
    String recipientAddress,
    double parsedAmount,
  ) {
    final pendingTransaction = _sendTransactionService.createPendingTransaction(
      transactionId: prepareResponse.transactionId,
      senderAddress: senderAddress,
      recipientAddress: recipientAddress,
      amount: prepareResponse.details.amount,
      tokenSymbol: _token!.symbol ?? '',
      blockchainName: _token!.blockchainName ?? '',
      prepareResponse: prepareResponse,
    );

    final historyProvider = Provider.of<HistoryProvider>(context, listen: false);
    historyProvider.addPendingTransaction(pendingTransaction);
  }

  // ==================== CONFIRM TRANSACTION ====================

  Future<void> onConfirmSend(BuildContext context) async {
    HapticFeedback.mediumImpact();
    if (_txDetails == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final walletName = await ServiceLocator.get<SecureStorage>().getSelectedWallet();
      if (walletName == null || walletName.isEmpty) {
        _showError('Wallet name not available');
        _isLoading = false;
        notifyListeners();
        return;
      }

      final result = await _sendTransactionService.confirmTransaction(
        walletName: walletName,
        userId: _userId,
        blockchainName: _token!.blockchainName ?? '',
        recipientAddress: _txDetails!.details.recipient,
        amount: _txDetails!.details.amount,
        smartContractAddress: _token!.smartContractAddress ?? '',
        transactionId: _txDetails!.transactionId,
      );

      if (result.success) {
        _handleConfirmSuccess(context);
      } else {
        _handleConfirmError(context, result.message ?? 'Unknown error occurred');
      }
    } catch (e) {
      _showError('Error confirming transaction: ${e.toString()}');
    }

    _isLoading = false;
    notifyListeners();
  }

  bool _transactionCompleted = false;
  bool get transactionCompleted => _transactionCompleted;

  void _handleConfirmSuccess(BuildContext context) {
    final historyProvider = Provider.of<HistoryProvider>(context, listen: false);
    _sendTransactionService.handleTransactionSuccess(
      historyManager: historyProvider,
      transactionId: _txDetails!.transactionId,
      sentAmount: double.tryParse(_txDetails!.details.amount) ?? 0,
      tokenSymbol: _token?.symbol ?? 'crypto',
    );

    _transactionCompleted = true;
    _currentStep = SendFlowStep.form;
    notifyListeners();
  }

  void _handleConfirmError(BuildContext context, String errorMessage) {
    if (errorMessage.contains('Network is currently experiencing issues') ||
        errorMessage.contains('Failed to broadcast transaction via Tatum API')) {
      _showTatumError(errorMessage);
    } else if (errorMessage.contains('Transaction has expired')) {
      _showError('Transaction Expired\n\nYour transaction has expired. Please create a new transaction.');
    } else if (errorMessage.contains('Insufficient balance')) {
      _showError(
          'Insufficient Balance\n\nYou don\'t have enough balance to complete this transaction. Please check your balance and try again.');
    } else if (errorMessage.contains('Invalid transaction data')) {
      _showError('Invalid Transaction\n\nPlease verify your recipient address and amount, then try again.');
    } else if (errorMessage.contains('Private key does not match')) {
      _showError(
          'Wallet Configuration Error\n\nThere appears to be a mismatch in wallet configuration. Please try restarting the app or contact support.');
    } else if (errorMessage.contains('not found') || errorMessage.contains('expired')) {
      _showError('Transaction Not Found\n\nThe transaction may have expired. Please create a new transaction.');
    } else {
      _showError('Transaction Failed\n\n$errorMessage');
    }
  }

  // ==================== RETRY BROADCAST ====================

  /// Retry broadcast without re-signing (sign once, broadcast many pattern).
  Future<String?> retryBroadcast(BuildContext context) async {
    if (_txDetails == null) return null;

    HapticFeedback.mediumImpact();
    _isLoading = true;
    notifyListeners();

    try {
      final txId = _txDetails!.transactionId;
      final hash = await ServiceLocator.get<LocalSendFacade>().retryBroadcast(txId);

      if (hash != null && hash.isNotEmpty) {
        final historyProvider = Provider.of<HistoryProvider>(context, listen: false);
        _sendTransactionService.handleTransactionSuccess(
          historyManager: historyProvider,
          transactionId: txId,
          sentAmount: double.tryParse(_txDetails!.details.amount) ?? 0,
          tokenSymbol: _token?.symbol ?? 'crypto',
        );

        _currentStep = SendFlowStep.form;
        notifyListeners();
        return hash;
      } else {
        _showError('Broadcast failed. Please try again.');
      }
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('expired') || errorStr.contains('unavailable') || errorStr.contains('not found')) {
        _showError(
          'Transaction Cannot Be Retried\n\n'
          '${e.toString()}\n\n'
          'Please go back and create a new transaction from the Send screen.',
        );
      } else {
        _showTatumError(errorStr);
      }
    }

    _isLoading = false;
    notifyListeners();
    return null;
  }

  // ==================== ERROR HANDLING ====================

  void _showError(String message) {
    String enhancedMessage = message;
    if (message.toLowerCase().contains('insufficient')) {
      enhancedMessage = message;
    }
    _errorMessage = enhancedMessage;
    _currentStep = SendFlowStep.error;
    notifyListeners();
  }

  bool _showTatumErrorDialog = false;
  bool get showTatumErrorDialog => _showTatumErrorDialog;
  String _tatumErrorMessage = '';
  String get tatumErrorMessage => _tatumErrorMessage;

  void _showTatumError(String errorMessage) {
    _tatumErrorMessage = errorMessage;
    _showTatumErrorDialog = true;
    notifyListeners();
  }

  void dismissTatumError() {
    _showTatumErrorDialog = false;
    notifyListeners();
  }

  // ==================== DISMISS MODALS ====================

  void dismissConfirm() {
    _currentStep = SendFlowStep.form;
    notifyListeners();
  }

  void dismissError() {
    _currentStep = SendFlowStep.form;
    notifyListeners();
  }

  void dismissSelfTransferError() {
    _currentStep = SendFlowStep.form;
    notifyListeners();
  }

  // ==================== UTILITY ====================

  String getDollarValue() {
    final price = _pricePerToken;
    final amountStr = amountController.text;
    final amt = double.tryParse(amountStr) ?? 0.0;
    final totalValue = price * amt;
    if (totalValue < 0.01) {
      return totalValue.toStringAsFixed(4);
    }
    return totalValue.toStringAsFixed(2);
  }

  String getBlockchainCurrency() {
    return _feeService.getBlockchainCurrency(_token?.blockchainName);
  }

  String formatAddress(String address) {
    return _addressValidation.formatAddress(address);
  }

  // ==================== DISPOSE ====================

  @override
  void dispose() {
    addressController.dispose();
    amountController.dispose();
    super.dispose();
  }
}

/// Internal helper to carry both the normalized name and resolved address.
class NormalizedAndAddress {
  final String normalizedName;
  final String address;

  NormalizedAndAddress({required this.normalizedName, required this.address});
}
