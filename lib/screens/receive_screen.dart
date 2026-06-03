import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../navigation/app_navigation.dart';
import '../navigation/route_paths.dart';
import 'package:http/http.dart' as http;

import '../services/secure_storage.dart';
import '../providers/price_provider.dart';
import '../utils/shared_preferences_utils.dart';
import '../wallet/address_registry.dart';
import '../wallet/wallet_mode.dart';
import '../widgets/filter_widgets.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  String searchText = '';
  String selectedNetwork = 'All Blockchains';
  bool isLoading = true;
  List<Map<String, dynamic>> tokens = [];
  Map<String, String> addressCache = {};
  String? userId;
  List<String> blockchains = ['All Blockchains'];

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
    _initUserAndLoadTokens();
  }

  Future<void> _initUserAndLoadTokens() async {
    setState(() => isLoading = true);
    
    // بارگذاری کیف پول انتخاب شده (مطابق با Kotlin)
    final selectedWallet = await SecureStorage.instance.getSelectedWallet();
    final selectedUserId = await SecureStorage.instance.getUserIdForSelectedWallet();
    
    if (selectedWallet != null && selectedUserId != null) {
      userId = selectedUserId;
      print('💰 Receive Screen - Loaded selected wallet: $selectedWallet with userId: $selectedUserId');
    } else {
      // Fallback: try to get from first available wallet
      final wallets = await SecureStorage.instance.getWalletsList();
      if (wallets.isNotEmpty) {
        final firstWallet = wallets.first;
        userId = firstWallet['userID'];
        print('⚠️ No selected wallet found, using first available wallet: ${firstWallet['walletName']}');
      }
    }
    
    print('UserID: ${userId ?? 'NULL'}');
    
    await _fetchTokensAndAddresses();
  }

  // --- کش لیست توکن‌ها (کریپتوها) ---
  Future<List<Map<String, dynamic>>> _loadTokensFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('crypto_tokens_cache');
    if (jsonStr == null) return [];
    final List<dynamic> list = jsonDecode(jsonStr);
    return List<Map<String, dynamic>>.from(list);
  }

  Future<void> _saveTokensToCache(List<Map<String, dynamic>> tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('crypto_tokens_cache', jsonEncode(tokens));
  }

  // --- کش آدرس‌های هر والت ---
  Future<Map<String, String>> _loadAddressesFromCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('wallet_addresses_cache_$userId');
    if (jsonStr == null) return {};
    final Map<String, dynamic> map = jsonDecode(jsonStr);
    return Map<String, String>.from(map);
  }

  Future<void> _saveAddressesToCache(String userId, Map<String, String> addresses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wallet_addresses_cache_$userId', jsonEncode(addresses));
  }

  Future<void> _fetchTokensAndAddresses() async {
    setState(() => isLoading = true);
    // 1. لیست توکن‌ها را از کش بخوان
    List<Map<String, dynamic>> tokensList = await _loadTokensFromCache();
    if (tokensList.isEmpty) {
      // اگر کش نبود، از سرور بگیر و کش کن
      final response = await http.get(Uri.parse('https://coinceeper.com/api/all-currencies'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> currencies = data['currencies'] ?? [];
        tokensList = currencies.map((e) => Map<String, dynamic>.from(e)).toList();
        await _saveTokensToCache(tokensList);
      }
    }
    Map<String, String> addresses = await _loadAddressesFromCache(userId ?? '');
    if (addresses.isEmpty && userId != null) {
      addresses = await AddressRegistry.instance.loadForWallet(userId!);
      final selectedWallet = await SecureStorage.instance.getSelectedWallet();
      if (addresses.isEmpty && selectedWallet != null) {
        final mnemonic = await SecureStorage.instance.getMnemonic(
          selectedWallet,
          userId!,
        );
        if (mnemonic != null && mnemonic.isNotEmpty) {
          await AddressRegistry.instance.deriveAndCache(
            userId: userId!,
            mnemonic: mnemonic,
          );
          addresses = await AddressRegistry.instance.loadForWallet(userId!);
        }
      }
      if (addresses.isNotEmpty) {
        await _saveAddressesToCache(userId!, addresses);
      }
    }
    // 3. مپ کردن توکن‌ها و آدرس‌ها برای نمایش
    List<Map<String, dynamic>> updatedTokens = [];
    Set<String> blockchainSet = {};
    for (final token in tokensList) {
      final blockchain = token['BlockchainName'] ?? '';
      blockchainSet.add(blockchain);
      final address = addresses[blockchain] ?? '';
      updatedTokens.add({
        'name': token['CurrencyName'] ?? '',
        'symbol': token['Symbol'] ?? '',
        'blockchain': blockchain,
        'icon': token['Icon'] ?? '',
        'address': address,
      });
    }
    setState(() {
      tokens = updatedTokens;
      blockchains = ['All Blockchains', ...blockchainSet];
      isLoading = false;
    });
  }

  List<Map<String, dynamic>> get filteredTokens {
    return tokens.where((token) {
      final matchesSearch = searchText.isEmpty ||
          token['symbol'].toString().toLowerCase().contains(searchText.toLowerCase()) ||
          token['name'].toString().toLowerCase().contains(searchText.toLowerCase());
      final matchesNetwork = selectedNetwork == 'All Blockchains' || token['blockchain'] == selectedNetwork;
      return matchesSearch && matchesNetwork;
    }).toList();
  }

  void _showNetworkSelector() {
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
                  children: blockchains.map((blockchain) => _ReceiveNetworkOption(
                    name: blockchain == 'All Blockchains' 
                        ? _safeTranslate('select_network', 'Select Network')
                        : blockchain,
                    icon: _getBlockchainIconPath(blockchain),
                    isSelected: selectedNetwork == blockchain,
                    onTap: () {
                      setState(() {
                        selectedNetwork = blockchain;
                      });
                      Navigator.pop(context);
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

  String _getBlockchainIconPath(String blockchain) {
    switch (blockchain) {
      case 'Bitcoin':
        return 'assets/images/btc.png';
      case 'Ethereum':
        return 'assets/images/ethereum_logo.png';
      case 'Binance Smart Chain':
        return 'assets/images/binance_logo.png';
      case 'Polygon':
        return 'assets/images/pol.png';
      case 'Tron':
        return 'assets/images/tron.png';
      case 'Arbitrum':
        return 'assets/images/arb.png';
      case 'XRP':
        return 'assets/images/xrp.png';
      case 'Avalanche':
        return 'assets/images/avax.png';
      case 'Polkadot':
        return 'assets/images/dot.png';
      case 'Solana':
        return 'assets/images/sol.png';
      default:
        return 'assets/images/all.png';
    }
  }

  Widget _blockchainIcon(String bc) {
    Widget iconWidget;
    switch (bc) {
      case 'Bitcoin':
        iconWidget = Image.asset('assets/images/btc.png', width: 24, height: 24, fit: BoxFit.contain);
        break;
      case 'Ethereum':
        iconWidget = Image.asset('assets/images/ethereum_logo.png', width: 24, height: 24, fit: BoxFit.contain);
        break;
      case 'Binance Smart Chain':
        iconWidget = Image.asset('assets/images/binance_logo.png', width: 24, height: 24, fit: BoxFit.contain);
        break;
      case 'Polygon':
        iconWidget = Image.asset('assets/images/pol.png', width: 24, height: 24, fit: BoxFit.contain);
        break;
      case 'Tron':
        iconWidget = Image.asset('assets/images/tron.png', width: 24, height: 24, fit: BoxFit.contain);
        break;
      case 'Arbitrum':
        iconWidget = Image.asset('assets/images/arb.png', width: 24, height: 24, fit: BoxFit.contain);
        break;
      case 'XRP':
        iconWidget = Image.asset('assets/images/xrp.png', width: 24, height: 24, fit: BoxFit.contain);
        break;
      case 'Avalanche':
        iconWidget = Image.asset('assets/images/avax.png', width: 24, height: 24, fit: BoxFit.contain);
        break;
      case 'Polkadot':
        iconWidget = Image.asset('assets/images/dot.png', width: 24, height: 24, fit: BoxFit.contain);
        break;
      case 'Solana':
        iconWidget = Image.asset('assets/images/sol.png', width: 24, height: 24, fit: BoxFit.contain);
        break;
      default:
        iconWidget = Image.asset('assets/images/all.png', width: 24, height: 24, fit: BoxFit.contain);
    }
    
    return ClipOval(
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: iconWidget,
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(_safeTranslate('receive_token', 'Receive Token'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: _safeTranslate('search', 'Search'),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0x25757575),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    ),
                    onChanged: (val) => setState(() => searchText = val),
                  ),
                  const SizedBox(height: 12),
                  BlockchainFilterChips(
                    selectedBlockchain: selectedNetwork,
                    blockchains: blockchains,
                    blockchainIcons: Map.fromIterable(
                      blockchains.where((b) => b != 'All Blockchains'),
                      key: (b) => b,
                      value: (b) => _getBlockchainIconPath(b),
                    ),
                    onChanged: (chain) {
                      setState(() => selectedNetwork = chain);
                    },
                    selectedColor: const Color(0xFF11c699),
                    allLabel: _safeTranslate('select_network', 'All Blockchains'),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredTokens.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final token = filteredTokens[index];
                        final address = token['address'] ?? '';
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            AppNavigation.pushNamed(
                              context,
                              RoutePaths.receiveWallet,
                              arguments: {
                                'cryptoName': token['name'],
                                'blockchainName': token['blockchain'],
                                'address': address,
                                'symbol': token['symbol'],
                              },
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F7F7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                            child: Row(
                              children: [
                                ClipOval(
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Image.network(
                                      token['icon'],
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${token['name']} (${token['symbol']})',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 1),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              address.length > 16 ? '${address.substring(0, 8)}...${address.substring(address.length - 5)}' : address,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                              style: const TextStyle(fontSize: 13, color: Colors.grey),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.qr_code, color: Colors.grey),
                                  onPressed: () {
                                    AppNavigation.pushNamed(
                                      context,
                                      RoutePaths.receiveWallet,
                                      arguments: {
                                        'cryptoName': token['name'],
                                        'blockchainName': token['blockchain'],
                                        'address': address,
                                        'symbol': token['symbol'],
                                      },
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, color: Colors.grey),
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: address));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(_safeTranslate('copied', 'Address copied to clipboard')),
                                        duration: const Duration(seconds: 2),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ReceiveNetworkOption extends StatelessWidget {
  final String name;
  final String icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ReceiveNetworkOption({
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