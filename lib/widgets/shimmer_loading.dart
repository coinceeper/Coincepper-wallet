import 'package:flutter/material.dart';

/// Lightweight shimmer/skeleton placeholder that mimics the layout
/// of the home token list while data loads.
///
/// Shows a stack of rounded rectangles with a subtle opacity animation
/// instead of a bare [CircularProgressIndicator].
class ShimmerTokenList extends StatefulWidget {
  const ShimmerTokenList({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  State<ShimmerTokenList> createState() => _ShimmerTokenListState();
}

class _ShimmerTokenListState extends State<ShimmerTokenList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.3 + (_controller.value * 0.4);
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: widget.itemCount,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, index) => _buildRow(opacity),
        );
      },
    );
  }

  Widget _buildRow(double opacity) {
    return Row(
      children: [
        // Circle avatar placeholder
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(opacity),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        // Text lines
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 14,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(opacity),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 12,
                width: 80,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(opacity),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Right-aligned balance text
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              height: 14,
              width: 70,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(opacity),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 12,
              width: 50,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(opacity),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Full-page shimmer placeholder for wallet or details screens.
class ShimmerPage extends StatelessWidget {
  const ShimmerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title bar placeholder
              Container(
                height: 24,
                width: 160,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 24),
              // Balance card placeholder
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(height: 24),
              // Token list placeholder
              Expanded(
                child: ShimmerTokenList(itemCount: 6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
