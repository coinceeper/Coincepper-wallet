import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/address_book_entry.dart';
import '../services/address_book_service.dart';

class EditAddressBookScreen extends StatefulWidget {
  final String walletName;
  final String walletAddress;
  const EditAddressBookScreen({super.key, required this.walletName, required this.walletAddress});

  @override
  State<EditAddressBookScreen> createState() => _EditAddressBookScreenState();
}

class _EditAddressBookScreenState extends State<EditAddressBookScreen> {
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  bool showDeleteDialog = false;

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
    _nameController = TextEditingController(text: widget.walletName);
    _addressController = TextEditingController(text: widget.walletAddress);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _save() async {
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    if (name.isNotEmpty && address.isNotEmpty) {
      // Editing address in AddressBookService should be handled by parent (in AddressBookScreen)
      Navigator.pop(context, {
        'name': name,
        'address': address,
        'deleted': false,
      });
    }
  }

  void _delete() async {
    // Deleting address in AddressBookService should be handled by parent (in AddressBookScreen)
    Navigator.pop(context, {
      'name': widget.walletName,
      'address': widget.walletAddress,
      'deleted': true,
    });
  }

  void _showDeleteModal() async {
    // Remove modal bottom sheet - delete confirmation removed
    _delete(); // Direct delete without confirmation
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _safeTranslate('edit_wallet', 'Edit Wallet'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _save,
                    child: Text(_safeTranslate('save', 'Save'), style: const TextStyle(fontSize: 16, color: Color(0xFF16B369))),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(_safeTranslate('wallet_name', 'Wallet Name'), style: const TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF16B369)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              Text(_safeTranslate('wallet_address', 'Wallet Address'), style: const TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF16B369)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                style: const TextStyle(fontSize: 16),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _showDeleteModal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC0303),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: Text(_safeTranslate('delete', 'Delete'), style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 