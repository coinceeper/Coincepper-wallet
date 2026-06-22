import 'package:flutter/material.dart';
import '../providers/view_models/home_view_model.dart';

/// Bottom sheet for filter and sort options in HomeScreen.
///
/// Extracted from HomeScreen to reduce HomeScreen's responsibility and
/// make the filter sheet independently reusable.
class FilterSheet extends StatelessWidget {
  final HomeViewModel viewModel;

  const FilterSheet({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sort by',
            style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onSurface),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['balance', 'name', 'price'].map((opt) {
              final isSelected = viewModel.sortOption == opt;
              return ChoiceChip(
                label: Text(opt),
                selected: isSelected,
                onSelected: (_) {
                  viewModel.setSortOption(opt);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('Hide zero balances'),
            value: viewModel.hideZeroBalances,
            onChanged: (_) {
              viewModel.toggleZeroBalances();
              Navigator.pop(context);
            },
          ),
          CheckboxListTile(
            title: const Text('Show only enabled'),
            value: viewModel.showOnlyEnabled,
            onChanged: (_) {
              viewModel.toggleShowOnlyEnabled();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
