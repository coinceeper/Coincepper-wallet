import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../layout/main_layout.dart';
import '../models/transaction.dart';
import '../providers/history_provider.dart';
import '../providers/price_provider.dart';
import '../screens/transaction_detail_screen.dart';
import 'package:go_router/go_router.dart';
import '../navigation/route_paths.dart';
import '../services/service_provider.dart';
import '../services/api_models.dart' as api;
import '../utils/transaction_cache.dart';
import '../utils/number_formatter.dart';
import '../services/secure_storage.dart';
import '../services/inbound_crypto_notifier.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool isLoading = true;
  bool isRefreshing = false;
  String? errorMessage;
  String selectedNetwork = "All Networks";
  List<Transaction> transactions = [];
  List<Transaction> localPendingTransactions = [];

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
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Get local pending transactions
      localPendingTransactions = TransactionCache.pendingTransactions;
      
      // Fetch transactions from API (مطابق با History.kt)
      final apiService = ServiceProvider.instance.apiService;
      final userId = await _getUserId();
      
      if (userId != null && userId.isNotEmpty) {
        print('📊 History Screen: Fetching transactions for user: $userId (matching History.kt)');
        
        // استفاده از getTransactions مطابق با کاتلین
        final request = api.TransactionsRequest(userID: userId);
        final response = await apiService.getTransactions(request);
        
        print('📊 History Screen: API response status: ${response.status}');
        print('📊 History Screen: Number of transactions: ${response.transactions.length}');
        
        if (response.status == "success") {
          // Convert API transactions to local transactions with null safety
          final localTransactions = response.transactions.map((apiTx) => Transaction(
            txHash: apiTx.txHash ?? '',
            from: apiTx.from ?? '',
            to: apiTx.to ?? '',
            amount: apiTx.amount ?? '0',
            tokenSymbol: apiTx.tokenSymbol ?? '',
            direction: apiTx.direction ?? 'unknown',
            status: apiTx.status ?? 'unknown',
            timestamp: apiTx.timestamp?.toString() ?? DateTime.now().toIso8601String(),
            blockchainName: apiTx.blockchainName ?? '',
            price: apiTx.price,
            temporaryId: apiTx.temporaryId,
          )).toList();
          
          print('📊 History Screen: Successfully converted ${localTransactions.length} transactions');
          
          // Debug: نمایش tokenSymbol های موجود برای کمک به debug
          final uniqueSymbols = localTransactions.map((tx) => tx.tokenSymbol).toSet();
          print('📊 History Screen: Unique token symbols found: $uniqueSymbols');
          
          // Update local cache with server data
          for (final localTx in localTransactions) {
            try {
              final matchedPending = localPendingTransactions.firstWhere(
                (pending) => pending.txHash == localTx.txHash,
                orElse: () => localTx,
              );
              // Create a new transaction with the temporary ID if needed
              final transactionToCache = matchedPending != localTx 
                  ? Transaction(
                      txHash: localTx.txHash,
                      from: localTx.from,
                      to: localTx.to,
                      amount: localTx.amount,
                      tokenSymbol: localTx.tokenSymbol,
                      direction: localTx.direction,
                      status: localTx.status,
                      timestamp: localTx.timestamp,
                      blockchainName: localTx.blockchainName,
                      price: localTx.price,
                      temporaryId: matchedPending.temporaryId,
                    )
                  : localTx;
              TransactionCache.updateById(localTx.txHash, transactionToCache);
              TransactionCache.matchAndReplacePending(localTx);
            } catch (e) {
              print('⚠️ History Screen: Error updating cache for transaction ${localTx.txHash}: $e');
            }
          }
          
          transactions = localTransactions;
          print('✅ History Screen: Successfully loaded ${transactions.length} transactions');
          await InboundCryptoNotifier.processInboundFromHistory(
            userId,
            localTransactions,
          );
        } else {
          print('❌ History Screen: API returned error status: ${response.status}');
          errorMessage = 'Failed to fetch transactions';
        }
      } else {
        print('❌ History Screen: No userId found');
        errorMessage = 'User ID not found';
      }
    } catch (e) {
      print('❌ History Screen: Error loading transactions: $e');
      errorMessage = e.toString();
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<String?> _getUserId() async {
    // دریافت userId انتخاب‌شده از SecureStorage
    return await SecureStorage.getUserId();
  }

  Future<void> _refreshTransactions() async {
    setState(() {
      isRefreshing = true;
    });

    await _loadTransactions();

    setState(() {
      isRefreshing = false;
    });
  }

  String _getDateGroup(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final transactionDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

      if (transactionDate.isAtSameMomentAs(today)) {
        return _safeTranslate('today', 'Today');
      } else if (transactionDate.isAtSameMomentAs(yesterday)) {
        return _safeTranslate('yesterday', 'Yesterday');
      } else {
        return DateFormat('MMM d, yyyy').format(dateTime);
      }
    } catch (e) {
      return _safeTranslate('unknown_date', 'Unknown Date');
    }
  }

  void _showFilterModal() {
    final networks = [
      {'name': 'All Networks', 'icon': 'assets/images/all.png'},
      {'name': 'Bitcoin', 'icon': 'assets/images/btc.png'},
      {'name': 'Ethereum', 'icon': 'assets/images/ethereum_logo.png'},
      {'name': 'Binance Smart Chain', 'icon': 'assets/images/binance_logo.png'},
      {'name': 'Polygon', 'icon': 'assets/images/pol.png'},
      {'name': 'Tron', 'icon': 'assets/images/tron.png'},
      {'name': 'Arbitrum', 'icon': 'assets/images/arb.png'},
      {'name': 'XRP', 'icon': 'assets/images/xrp.png'},
      {'name': 'Avalanche', 'icon': 'assets/images/avax.png'},
      {'name': 'Polkadot', 'icon': 'assets/images/dot.png'},
      {'name': 'Solana', 'icon': 'assets/images/sol.png'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11c699).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.language,
                      color: Color(0xFF11c699),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _safeTranslate('select_network', 'Select Network'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
            
            // Network options
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: networks.map((network) => _HistoryNetworkOption(
                    name: network['name'] == 'All Networks' 
                        ? _safeTranslate('select_network', 'Select Network')
                        : network['name']!,
                    icon: network['icon']!,
                    isSelected: selectedNetwork == network['name'],
                    onTap: () {
                      setState(() {
                        selectedNetwork = network['name']!;
                      });
                      context.pop();
                    },
                  )).toList(),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshTransactions,
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 16, bottom: 12, left: 16, right: 16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
                      ),
                      Expanded(
                        child: Text(
                          _safeTranslate('history', 'History'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 24), // برای تعادل با دکمه back
                    ],
                  ),
                ),

                // Filter
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GestureDetector(
                    onTap: _showFilterModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F3F4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            selectedNetwork == 'All Networks' 
                                ? _safeTranslate('select_network', 'Select Network')
                                : selectedNetwork,
                            style: const TextStyle(fontSize: 14, color: Colors.black),
                          ),
                          const Spacer(),
                          const Icon(Icons.arrow_drop_down, color: Colors.black, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildContent(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF11c699)),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Text(
          "Error: $errorMessage",
          style: const TextStyle(color: Colors.red, fontSize: 16),
        ),
      );
    }

    // Combine local pending and server transactions
    final allTransactions = <dynamic>{...localPendingTransactions, ...transactions}
        .toList()
        .where((tx) => selectedNetwork == "All Networks" || tx.blockchainName == selectedNetwork)
        .toList()
      ..sort((a, b) => DateTime.parse(b.timestamp).compareTo(DateTime.parse(a.timestamp)));

    if (allTransactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/notransaction.png',
              width: 180,
              height: 180,
            ),
            const SizedBox(height: 16),
            Text(
              _safeTranslate('no_transactions_found', 'No transactions found'),
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Group transactions by date
    final grouped = <String, List<Transaction>>{};
    for (final transaction in allTransactions) {
      final dateGroup = _getDateGroup(transaction.timestamp);
      grouped.putIfAbsent(dateGroup, () => []).add(transaction);
    }

    return ListView.builder(
      itemCount: grouped.length + 1, // +1 for the footer
      itemBuilder: (context, index) {
        if (index == grouped.length) {
          // Footer
          return Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x0F1BCAA0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _safeTranslate('cannot_find_transaction', 'Cannot find your transaction? '),
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                GestureDetector(
                  onTap: () {
                    // Open explorer functionality
                  },
                  child: Text(
                    _safeTranslate('check_explorer', 'Check explorer'),
                    style: const TextStyle(
                      color: Color(0xFF11c699),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final dateGroup = grouped.keys.elementAt(index);
        final transactions = grouped[dateGroup]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                dateGroup,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ),
            ...transactions.map((transaction) => _HistoryTransactionItem(
              transaction: transaction,
              onTap: () {
                _navigateToTransactionDetail(transaction);
              },
            )),
          ],
        );
      },
    );
  }

  void _navigateToTransactionDetail(Transaction transaction) {
    print('🔍 History: Navigating to transaction detail for: ${transaction.txHash}');
    
    // استفاده از route جدید که از API جزئیات کامل تراکنش (شامل explorerUrl) را دریافت می‌کند
    context.push(
      RoutePaths.transactionDetail,
      extra: {
        'transactionId': transaction.txHash, // ارسال txHash برای دریافت جزئیات از API
      },
    );
  }
}

class _HistoryTransactionItem extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback onTap;

  const _HistoryTransactionItem({
    required this.transaction,
    required this.onTap,
  });

  // Safe translate method with fallback
  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  String _formatAmount(String amount) {
    return NumberFormatter.formatAmount(amount);
  }

  @override
  Widget build(BuildContext context) {
    final isReceived = transaction.direction == "inbound";
    final amountPrefix = isReceived ? "+" : "-";
    final formattedAmount = _formatAmount(transaction.amount);
    final amountValue = "$amountPrefix$formattedAmount";
    final tokenSymbol = transaction.tokenSymbol;
    
    // Calculate fiat value with selected currency - will be handled in Consumer

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Icon
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isReceived 
                    ? const Color(0xFF20CDA4).withOpacity(0.1)
                    : const Color(0xFFF43672).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isReceived ? Icons.arrow_downward : Icons.arrow_upward,
                color: isReceived ? const Color(0xFF20CDA4) : const Color(0xFFF43672),
                size: 16,
              ),
            ),
            
            const SizedBox(width: 10),
            
            // Transaction info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isReceived ? _safeTranslate(context, 'receive', 'Receive') : _safeTranslate(context, 'send', 'Send'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      if (!isReceived && transaction.status.toLowerCase() == "pending") ...[
                        const SizedBox(width: 6),
                        Text(
                          _safeTranslate(context, 'pending', 'pending'),
                          style: const TextStyle(
                            color: Color(0xFFF9A825),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    "${isReceived ? _safeTranslate(context, 'from', 'From: ') : _safeTranslate(context, 'to', 'To: ')}${_getShortAddress(context, isReceived ? transaction.from : transaction.to)}",
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            
            // Amount and fiat value
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Text(
                      amountValue,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: amountValue.startsWith("-") 
                            ? const Color(0xFFF43672) 
                            : const Color(0xFF11c699),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      tokenSymbol,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                Consumer<PriceProvider>(
                  builder: (context, priceProvider, child) {
                    final currencySymbol = priceProvider.getCurrencySymbol();
                    try {
                      final price = transaction.price ?? 0.0;
                      if (price > 0.0) {
                        final value = price * double.parse(transaction.amount);
                        return Text(
                          "≈ $currencySymbol${value.toStringAsFixed(2)}",
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        );
                      } else {
                        return Text(
                          "≈ $currencySymbol${0.00.toStringAsFixed(2)}",
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        );
                      }
                    } catch (e) {
                      return Text(
                        "≈ $currencySymbol${0.00.toStringAsFixed(2)}",
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getShortAddress(BuildContext context, String? address) {
    if (address == null || address.isEmpty) return _safeTranslate(context, 'unknown', 'Unknown');
    if (address.length > 15) {
      return "${address.substring(0, 10)}...${address.substring(address.length - 5)}";
    }
    return address;
  }
}

class _HistoryNetworkOption extends StatelessWidget {
  final String name;
  final String icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _HistoryNetworkOption({
    required this.name,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF11c699).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Image.asset(
              icon,
              width: 24,
              height: 24,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.language, size: 24, color: Colors.grey);
              },
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? const Color(0xFF11c699) : Colors.black,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF11c699),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
} 