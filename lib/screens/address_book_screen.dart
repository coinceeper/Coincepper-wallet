import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../navigation/route_paths.dart';
import '../layout/bottom_menu_with_siri.dart';
import '../models/address_book_entry.dart';
import '../services/address_book_service.dart';

class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({super.key});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  List<AddressBookEntry> wallets = [];

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
    _loadWallets();
  }

  Future<void> _loadWallets() async {
    final loaded = await AddressBookService.loadWalletsFromKeystore();
    setState(() {
      wallets = loaded;
    });
  }

  Future<void> _addWallet(AddressBookEntry wallet) async {
    await AddressBookService.saveWalletToKeystore(wallet.name, wallet.address);
    await _loadWallets();
  }

  Future<void> _updateWallet(String oldName, AddressBookEntry wallet) async {
    if (oldName != wallet.name) {
      await AddressBookService.deleteWalletFromKeystore(oldName);
    }
    await AddressBookService.saveWalletToKeystore(wallet.name, wallet.address);
    await _loadWallets();
  }

  Future<void> _deleteWallet(String walletName) async {
    // Remove dialog - direct delete without confirmation
    await AddressBookService.deleteWalletFromKeystore(walletName);
    await _loadWallets();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(_safeTranslate('address_book', 'Address Book'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: Image.asset('assets/images/plus.png', width: 18, height: 18, color: const Color(0x99757575)),
            onPressed: () async {
              final result = await context.push<Object?>(RoutePaths.addAddress);
              if (result != null && result is Map<String, String>) {
                await _addWallet(AddressBookEntry(name: result['name']!, address: result['address']!));
              }
            },
          ),
        ],
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: wallets.isEmpty
            ? _EmptyAddressBook(
                safeTranslate: _safeTranslate,
                onAdd: () async {
                  final result = await context.push<Object?>(RoutePaths.addAddress);
                  if (result != null && result is Map<String, String>) {
                    await _addWallet(AddressBookEntry(name: result['name']!, address: result['address']!));
                  }
                })
            : ListView.separated(
                itemCount: wallets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final wallet = wallets[index];
                  return _WalletItem(
                    walletName: wallet.name,
                    walletAddress: wallet.address,
                    onTap: () async {
                      final result = await context.push<Object?>(
                        RoutePaths.editAddress,
                        extra: {
                          'walletName': wallet.name,
                          'walletAddress': wallet.address,
                        },
                      );
                      if (result != null && result is Map<String, dynamic>) {
                        if (result['deleted'] == true) {
                          await _deleteWallet(wallet.name);
                        } else {
                          await _updateWallet(wallet.name, AddressBookEntry(name: result['name'], address: result['address']));
                        }
                      }
                    },
                  );
                },
              ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }
}

class _EmptyAddressBook extends StatelessWidget {
  final VoidCallback onAdd;
  final String Function(String, String) safeTranslate;
  const _EmptyAddressBook({required this.onAdd, required this.safeTranslate});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),
        Image.asset('assets/images/addaddress.png', width: 200, height: 200),
        const SizedBox(height: 16),
        Text(
          safeTranslate('your_contacts_appear_here', 'Your contacts and their wallet address will appear here.'),
          style: const TextStyle(fontSize: 14, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16B369),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              elevation: 0,
            ),
            child: Text(safeTranslate('add_wallet_address', 'Add wallet address'), style: const TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 150),
      ],
    );
  }
}

class _WalletItem extends StatelessWidget {
  final String walletName;
  final String walletAddress;
  final VoidCallback onTap;
  const _WalletItem({required this.walletName, required this.walletAddress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF08C495), Color(0xFF39b6fb)]),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(walletName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(walletAddress, style: const TextStyle(fontSize: 14, color: Colors.white)),
                ],
              ),
            ),
            Image.asset('assets/images/rightarrow.png', width: 24, height: 24, color: Colors.white),
          ],
        ),
      ),
    );
  }
} 