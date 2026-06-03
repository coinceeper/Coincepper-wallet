import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/price_provider.dart';
import '../utils/shared_preferences_utils.dart';

class ReceiveWalletScreen extends StatefulWidget {
  final String cryptoName;
  final String blockchainName;
  final String address;
  final String symbol;
  final double? amount;
  const ReceiveWalletScreen({super.key, required this.cryptoName, required this.blockchainName, required this.address, required this.symbol, this.amount});

  @override
  State<ReceiveWalletScreen> createState() => _ReceiveWalletScreenState();
}

class _ReceiveWalletScreenState extends State<ReceiveWalletScreen> {
  String amount = '';
  bool showAmountDialog = false;
  bool copied = false;
  final GlobalKey _qrKey = GlobalKey();
  String selectedCurrency = 'USD';
  double tokenPrice = 0.0;
  bool isPriceLoading = true;

  @override
  void initState() {
    super.initState();
    // Initialize amount if provided
    if (widget.amount != null) {
      amount = widget.amount.toString();
    }
    _loadSelectedCurrency();
    _fetchTokenPrice();
  }

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  /// بارگذاری ارز انتخابی (مطابق با Kotlin recieve_wallet.kt)
  Future<void> _loadSelectedCurrency() async {
    try {
      selectedCurrency = await SharedPreferencesUtils.getSelectedCurrency();
      setState(() {});
      print('💰 ReceiveWallet Screen - Loaded selected currency: $selectedCurrency');
    } catch (e) {
      print('❌ Error loading selected currency: $e');
      selectedCurrency = 'USD'; // fallback
    }
  }

  /// دریافت قیمت توکن خاص (مطابق با Kotlin recieve_wallet.kt)
  Future<void> _fetchTokenPrice() async {
    setState(() {
      isPriceLoading = true;
    });

    try {
      print('🔄 ReceiveWallet Screen: Fetching price for token: ${widget.symbol} (matching Kotlin recieve_wallet.kt)');
      
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      
      // دریافت قیمت فقط برای این توکن مطابق با Kotlin recieve_wallet.kt
      await priceProvider.fetchPrices([widget.symbol], currencies: [selectedCurrency]);
      
      final price = priceProvider.getPriceForCurrency(widget.symbol, selectedCurrency);
      
      setState(() {
        tokenPrice = price ?? 0.0;
        isPriceLoading = false;
      });
      
      if (price != null && price > 0.0) {
        print('✅ ReceiveWallet Screen: Price for ${widget.symbol}: $price $selectedCurrency');
      } else {
        print('⚠️ ReceiveWallet Screen: No price found for ${widget.symbol}');
      }
    } catch (e) {
      print('❌ ReceiveWallet Screen: Error fetching price: $e');
      setState(() {
        tokenPrice = 0.0;
        isPriceLoading = false;
      });
    }
  }

  void _showAmountModal() async {
    final TextEditingController amountController = TextEditingController(text: amount);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(25),
              topRight: Radius.circular(25),
            ),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Colors.blue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _safeTranslate('set_amount', 'Set Amount'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.cryptoName} (${widget.symbol})',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Amount input section
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 28,
                      fontWeight: FontWeight.w400,
                    ),
                    suffixText: widget.symbol,
                    suffixStyle: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(20),
                  ),
                  onChanged: (value) {
                    setModalState(() {});
                  },
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Quick amount buttons
              Row(
                children: [
                  _quickAmountButton('0.1', amountController, setModalState),
                  const SizedBox(width: 8),
                  _quickAmountButton('1', amountController, setModalState),
                  const SizedBox(width: 8),
                  _quickAmountButton('10', amountController, setModalState),
                  const SizedBox(width: 8),
                  _quickAmountButton('100', amountController, setModalState),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Price estimation
              if (tokenPrice > 0.0 && amountController.text.isNotEmpty)
                Consumer<PriceProvider>(
                  builder: (context, priceProvider, child) {
                    final amountValue = double.tryParse(amountController.text) ?? 0.0;
                    final totalValue = amountValue * tokenPrice;
                    final currencySymbol = priceProvider.getCurrencySymbolForCurrency(selectedCurrency);
                    
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue[600],
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_safeTranslate('estimated_value', 'Estimated value')}: $currencySymbol${totalValue.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              
              if (tokenPrice > 0.0 && amountController.text.isNotEmpty)
                const SizedBox(height: 20),
              
              if (amountController.text.isNotEmpty)
                const SizedBox(height: 4),
              
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_safeTranslate('cancel', 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          amount = amountController.text;
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_safeTranslate('set_amount', 'Set Amount')),
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

  Widget _quickAmountButton(String amountText, TextEditingController controller, StateSetter setModalState) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          controller.text = amountText;
          setModalState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            amountText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareQrAndAddress() async {
    try {
      print('🚀 Starting share process...');
      
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Text(_safeTranslate('preparing_share', 'Preparing share...')),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 1),
          ),
        );
      }

      // Create comprehensive share message
      String message = '💰 ${_safeTranslate('payment_request', 'Payment Request')}\n\n';
      message += '🔗 ${_safeTranslate('wallet_address', 'Wallet Address')}:\n${widget.address}\n\n';
      message += '💎 ${_safeTranslate('cryptocurrency', 'Cryptocurrency')}: ${widget.cryptoName} (${widget.symbol})\n';
      message += '🌐 ${_safeTranslate('network', 'Network')}: ${widget.blockchainName}\n';
      
      if (amount.isNotEmpty && double.tryParse(amount) != null) {
        message += '💵 ${_safeTranslate('amount', 'Amount')}: $amount ${widget.symbol}\n';
      }
      
      message += '\n📱 ${_safeTranslate('scan_qr_instruction', 'Please scan the QR code or copy the address above to send payment.')}\n';
      message += '\n🔒 ${_safeTranslate('security_warning', 'Always verify the address before sending funds.')}';
      
      print('📝 Message prepared: ${message.substring(0, 50)}...');
      
      // Add small delay to ensure UI updates
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Use Share.share() with proper configuration
      final result = await Share.share(
        message,
        subject: '${_safeTranslate('wallet_address', 'Wallet Address')} - ${widget.cryptoName}',
        sharePositionOrigin: _getSharePositionOrigin(),
      );
      
      print('✅ Share result: ${result.status}');
      
      if (mounted) {
        // Hide loading indicator
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        // Show success message based on result
        if (result.status == ShareResultStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_safeTranslate('share_success', 'Successfully shared!')),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (result.status == ShareResultStatus.dismissed) {
          // User dismissed the share dialog - this is normal, no error message needed
          print('📱 User dismissed share dialog');
        }
      }
      
    } catch (e, stackTrace) {
      print('❌ Share error: $e');
      print('📚 Stack trace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      
      // More specific error handling
      if (e.toString().contains('No Activity found') || 
          e.toString().contains('ActivityNotFoundException')) {
        // No share apps available - offer clipboard as alternative
        _showShareAlternativeDialog();
      } else {
        // Other errors - try clipboard fallback
        _handleShareFallback(e);
      }
    }
  }

  /// Get share position origin for better share dialog positioning
  Rect? _getSharePositionOrigin() {
    try {
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        final Offset position = box.localToGlobal(Offset.zero);
        return Rect.fromLTWH(
          position.dx,
          position.dy,
          box.size.width,
          box.size.height,
        );
      }
    } catch (e) {
      print('⚠️ Could not get share position: $e');
    }
    return null;
  }

  /// Show dialog when no share apps are available
  void _showShareAlternativeDialog() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue[600]),
            const SizedBox(width: 8),
            Text(_safeTranslate('no_share_apps', 'No Share Apps')),
          ],
        ),
        content: Text(
          _safeTranslate('no_share_apps_message', 'No apps available for sharing. Would you like to copy the address to clipboard instead?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_safeTranslate('cancel', 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _copyToClipboard();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text(_safeTranslate('copy_address', 'Copy Address')),
          ),
        ],
      ),
    );
  }

  /// Handle share fallback scenarios
  void _handleShareFallback(dynamic error) async {
    try {
      print('🔄 Handling share fallback...');
      await _copyToClipboard();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_safeTranslate('share_failed_copied', 'Share unavailable. Address copied to clipboard.')),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: _safeTranslate('ok', 'OK'),
              textColor: Colors.white,
              onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            ),
          ),
        );
      }
    } catch (clipboardError) {
      print('❌ Clipboard error: $clipboardError');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_safeTranslate('share_and_copy_failed', 'Share and clipboard both failed')),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Copy address to clipboard with user feedback
  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.address));
    print('📋 Address copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final qrData = amount.isEmpty ? widget.address : "${widget.address}?amount=$amount";
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(_safeTranslate('receive', 'Receive'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Image.asset('assets/images/danger.png', width: 28, height: 28, color: const Color(0xFFE68A00)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _safeTranslate('only_send_assets_warning', 'Only send ({blockchain}) assets to this address.\nOther assets will be lost forever.').replaceAll('{blockchain}', widget.blockchainName),
                      style: const TextStyle(fontSize: 13, color: Color(0xFFE68A00)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(widget.cryptoName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(widget.blockchainName, style: const TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
              ),
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: _qrKey,
                child: Container(
                  color: Colors.white,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40), // گوشه‌های نرم
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 220,
                      gapless: false,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              widget.address,
              style: const TextStyle(fontSize: 15, color: Colors.black),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: Icons.copy,
                  label: copied ? _safeTranslate('copied', 'Copied!') : _safeTranslate('copy', 'Copy'),
                  onTap: () async {
                    await _copyToClipboard();
                    if (!mounted) return;
                    
                    setState(() { copied = true; });
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(_safeTranslate('address_copied', 'Address copied to clipboard')),
                          ],
                        ),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted) setState(() => copied = false);
                    });
                  },
                ),
                _ActionButton(
                  icon: Icons.edit,
                  label: _safeTranslate('set_amount', 'Set Amount'),
                  onTap: _showAmountModal,
                ),
                _ActionButton(
                  icon: Icons.share,
                  label: _safeTranslate('share', 'Share'),
                  onTap: _shareQrAndAddress,
                ),
              ],
            ),
            if (amount.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$amount ${widget.cryptoName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() => amount = ''),
                          child: const Icon(Icons.cancel, size: 20, color: Colors.grey),
                        ),
                      ],
                    ),
                    // نمایش تقریبی قیمت مقدار وارد شده
                    if (tokenPrice > 0.0)
                      Consumer<PriceProvider>(
                        builder: (context, priceProvider, child) {
                          final amountValue = double.tryParse(amount) ?? 0.0;
                          final totalValue = amountValue * tokenPrice;
                          final currencySymbol = priceProvider.getCurrencySymbolForCurrency(selectedCurrency);
                          
                          return Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              '~ $currencySymbol${totalValue.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFF7F7F7),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: Colors.black),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _AmountDialog extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onDone;
  final VoidCallback onCancel;
  const _AmountDialog({required this.initial, required this.onDone, required this.onCancel});

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late TextEditingController _controller;

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
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_safeTranslate('enter_amount', 'Enter Amount'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _safeTranslate('amount', 'Amount'),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: widget.onCancel, child: Text(_safeTranslate('cancel', 'Cancel'))),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => widget.onDone(_controller.text),
                  child: Text(_safeTranslate('ok', 'OK')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 