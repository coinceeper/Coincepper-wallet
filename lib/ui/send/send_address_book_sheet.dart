import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/view_models/send_detail_view_model.dart';
import '../../models/address_book_entry.dart';

/// Bottom sheet showing the address book for quick address selection.
class SendAddressBookSheet extends StatelessWidget {
  const SendAddressBookSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewModel = context.watch<SendDetailViewModel>();
    final addressBook = viewModel.addressBook;

    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(color: scheme.onSurface.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 40),
                const Text('Address Book', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: viewModel.toggleAddressBook,
                ),
              ],
            ),
          ),
          Expanded(
            child: addressBook.isEmpty
                ? _EmptyAddressBook(scheme: scheme)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: addressBook.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _AddressBookItem(
                        entry: addressBook[index],
                        onTap: () => viewModel.onSelectAddress(addressBook[index].address),
                        formattedAddress: viewModel.formatAddress(addressBook[index].address),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _EmptyAddressBook extends StatelessWidget {
  final ColorScheme scheme;

  const _EmptyAddressBook({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contacts_outlined, size: 64, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'No saved addresses',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Add addresses to your address book for quick access',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AddressBookItem extends StatelessWidget {
  final AddressBookEntry entry;
  final VoidCallback onTap;
  final String formattedAddress;

  const _AddressBookItem({
    required this.entry,
    required this.onTap,
    required this.formattedAddress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF08C495), Color(0xFF39b6fb)]),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(formattedAddress, style: const TextStyle(fontSize: 12, color: Colors.white)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}
