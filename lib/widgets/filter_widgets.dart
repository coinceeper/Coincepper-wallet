import 'package:flutter/material.dart';

// =============================================================================
// 🌐 BLOCKCHAIN FILTER CHIPS — reusable component
// =============================================================================

/// A horizontal row of [ChoiceChip] widgets for filtering by blockchain.
///
/// Designed to match the style used in PriceAlertsScreen's `_CreateAlertSheet`.
/// Supply [blockchains] as sorted strings (including the "All" option),
/// [blockchainIcons] maps chain name → asset path (optional; missing entries
/// render text-only chips), and [selectedColor] controls the active‑chip fill.
class BlockchainFilterChips extends StatelessWidget {
  final String selectedBlockchain;
  final List<String> blockchains;
  final Map<String, String> blockchainIcons;
  final ValueChanged<String> onChanged;
  final Color selectedColor;
  final String allLabel;

  /// Default set of known blockchain icons used across the app.
  static const Map<String, String> defaultIcons = {
    'Bitcoin': 'assets/images/btc.png',
    'Ethereum': 'assets/images/ethereum_logo.png',
    'BSC': 'assets/images/binance_logo.png',
    'Binance Smart Chain': 'assets/images/binance_logo.png',
    'Solana': 'assets/images/sol.png',
    'Tron': 'assets/images/tron.png',
    'Ripple': 'assets/images/xrp.png',
    'Polygon': 'assets/images/pol.png',
    'Avalanche': 'assets/images/avax.png',
    'Arbitrum': 'assets/images/arb.png',
    'Polkadot': 'assets/images/dot.png',
    'Litecoin': 'assets/images/litecoin_logo.png',
  };

  const BlockchainFilterChips({
    super.key,
    required this.selectedBlockchain,
    required this.blockchains,
    required this.onChanged,
    this.blockchainIcons = defaultIcons,
    this.selectedColor = const Color(0xFF0BAB9B),
    this.allLabel = 'All',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: blockchains.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chain = blockchains[index];
          final isSelected = selectedBlockchain == chain;
          final isAll = chain == 'All' ||
              chain == 'All Blockchains' ||
              chain == 'All Networks';
          final iconPath =
              isAll ? null : (blockchainIcons[chain] ?? blockchainIcons[chain]);

          return ChoiceChip(
            label: Padding(
              padding: EdgeInsets.only(left: iconPath != null ? 4 : 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (iconPath != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        iconPath,
                        width: 16,
                        height: 16,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox(width: 16, height: 16),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(isAll ? allLabel : chain),
                ],
              ),
            ),
            selected: isSelected,
            onSelected: (val) {
              if (val) onChanged(chain);
            },
            selectedColor: selectedColor,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
            backgroundColor: const Color(0xFFF5F7FA),
            side: BorderSide.none,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
          );
        },
      ),
    );
  }
}

/// Widget آیکون فیلتر
class FilterIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;

  const FilterIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 20,
            color: isActive ? const Color(0xFF11c699) : Colors.grey[400],
          ),
        ),
      ),
    );
  }
}

/// Widget چیپ فیلتر
class FilterChipWidget extends StatelessWidget {
  final String label;
  final VoidCallback onDeleted;

  const FilterChipWidget({
    super.key,
    required this.label,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: onDeleted,
      backgroundColor: const Color(0xFF11c699).withOpacity(0.1),
      deleteIconColor: const Color(0xFF11c699),
      side: const BorderSide(color: Color(0xFF11c699), width: 1),
    );
  }
}

/// Widget گزینه مرتب‌سازی
class SortOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final String currentValue;
  final ValueChanged<String> onChanged;

  const SortOptionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == currentValue;
    
    return InkWell(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF11c699).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? const Color(0xFF11c699) : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? const Color(0xFF11c699) : Colors.grey,
                    ),
                  ),
                ],
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
