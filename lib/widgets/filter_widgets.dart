import 'package:flutter/material.dart';

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
