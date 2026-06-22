import 'package:flutter/material.dart';

/// A horizontal, scrollable row of blockchain filter chips.
///
/// The currently selected chip is rendered with a filled background in
/// [selectedColor]; all other chips show a bordered outline.  An "All" chip
/// is always prepended so the user can clear the filter.
class BlockchainFilterChips extends StatelessWidget {
  /// The currently active blockchain, or `'All'` when no filter is applied.
  final String selectedBlockchain;

  /// The list of blockchain names to show as chips (excluding "All").
  final List<String> blockchains;

  /// Maps each blockchain name to an [IconData] for the chip's leading icon.
  final Map<String, IconData> blockchainIcons;

  /// Called when the user taps a chip.  Receives the chip's label (e.g.
  /// `'All'`, `'Ethereum'`, …).
  final ValueChanged<String> onChanged;

  /// Background colour for the selected chip.
  ///
  /// Defaults to the brand-teal value used across the app.
  final Color selectedColor;

  /// Label for the "All" chip (e.g. `'All Blockchains'`).
  final String allLabel;

  const BlockchainFilterChips({
    super.key,
    required this.selectedBlockchain,
    required this.blockchains,
    required this.blockchainIcons,
    required this.onChanged,
    this.selectedColor = const Color(0xFF08C495),
    this.allLabel = 'All',
  });

  /// A sensible default icon map covering well-known networks.
  static Map<String, IconData> get defaultIcons => const {
        'Bitcoin': Icons.currency_bitcoin,
        'Ethereum': Icons.token,
        'BNB Smart Chain': Icons.hexagon,
        'Solana': Icons.circle,
        'Polygon': Icons.change_circle,
        'Avalanche': Icons.av_timer,
        'Arbitrum': Icons.arrow_circle_right,
        'Optimism': Icons.arrow_upward,
        'Cronos': Icons.timer,
        'Fantom': Icons.flash_on,
        'Tron': Icons.wb_sunny,
        'Near': Icons.near_me,
        'Aptos': Icons.rocket_launch,
        'Sui': Icons.waves,
        'Cosmos': Icons.public,
        'Polkadot': Icons.donut_large,
        'Cardano': Icons.currency_exchange,
        'Algorand': Icons.check_circle,
        'Stellar': Icons.star,
        'Tezos': Icons.layers,
        'Litecoin': Icons.monetization_on,
        'Dogecoin': Icons.pets,
        'Ripple': Icons.swap_horiz,
        'Base': Icons.square_foot,
        'zkSync': Icons.vertical_align_center,
        'Linea': Icons.horizontal_rule,
        'Scroll': Icons.unfold_more,
        'Manta': Icons.water,
        'Blast': Icons.local_fire_department,
        'Sei': Icons.swap_vert,
      };

  @override
  Widget build(BuildContext context) {
    final chips = [allLabel, ...blockchains];

    final theme = Theme.of(context);
    final borderColor = theme.brightness == Brightness.dark
        ? Colors.white24
        : Colors.grey.withOpacity(0.4);

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = chips[index];
          final isSelected = selectedBlockchain == label;
          final icon = blockchainIcons[label];

          return _ChipButton(
            label: label,
            icon: icon,
            isSelected: isSelected,
            selectedColor: selectedColor,
            borderColor: borderColor,
            onTap: () => onChanged(label),
          );
        },
      ),
    );
  }
}

/// A single chip button used inside [BlockchainFilterChips].
///
/// Extracted as a private widget so the outer widget stays focused on layout
/// and the build function for each chip can be kept lean.
class _ChipButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final Color selectedColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _ChipButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.selectedColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isSelected ? Colors.white : Theme.of(context).textTheme.bodySmall?.color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? selectedColor : borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: textColor),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
