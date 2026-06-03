import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/price_provider.dart';
import '../utils/number_formatter.dart';

/// 📊 Simple Price Chart Widget
/// Shows price trend using available price data
class SimplePriceChart extends StatefulWidget {
  final String symbol;
  final double height;
  final Color primaryColor;

  const SimplePriceChart({
    super.key,
    required this.symbol,
    this.height = 250,
    this.primaryColor = const Color(0xFF0BAB9B),
  });

  @override
  State<SimplePriceChart> createState() => _SimplePriceChartState();
}

class _SimplePriceChartState extends State<SimplePriceChart>
    with SingleTickerProviderStateMixin {
  
  String selectedTimeframe = '1D';
  final List<String> timeframes = ['1H', '4H', '1D', '1W', '1M', '3M'];
  
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// 📊 Generate sample chart data based on current price
  List<ChartPoint> _generateChartData(double currentPrice) {
    final points = <ChartPoint>[];
    final now = DateTime.now();
    
    // Generate points based on timeframe
    int pointCount;
    Duration interval;
    
    switch (selectedTimeframe) {
      case '1H':
        pointCount = 12;
        interval = const Duration(minutes: 5);
        break;
      case '4H':
        pointCount = 24;
        interval = const Duration(minutes: 10);
        break;
      case '1D':
        pointCount = 24;
        interval = const Duration(hours: 1);
        break;
      case '1W':
        pointCount = 7;
        interval = const Duration(days: 1);
        break;
      case '1M':
        pointCount = 30;
        interval = const Duration(days: 1);
        break;
      case '3M':
        pointCount = 90;
        interval = const Duration(days: 1);
        break;
      default:
        pointCount = 24;
        interval = const Duration(hours: 1);
    }
    
    // Generate realistic price variations
    for (int i = 0; i < pointCount; i++) {
      final timestamp = now.subtract(interval * (pointCount - 1 - i));
      
      // Create realistic price movement
      final variation = (i / pointCount - 0.5) * 0.1; // ±5% variation
      final noise = (i % 3 - 1) * 0.02; // Small random-like noise
      final price = currentPrice * (1 + variation + noise);
      
      points.add(ChartPoint(
        timestamp: timestamp,
        price: price,
        volume: 1000000.0 + (i * 50000),
      ));
    }
    
    return points;
  }

  /// 🎨 Build timeframe selector
  Widget _buildTimeframeSelector() {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: timeframes.length,
        itemBuilder: (context, index) {
          final timeframe = timeframes[index];
          final isSelected = timeframe == selectedTimeframe;
          
          return GestureDetector(
            onTap: () {
              if (timeframe != selectedTimeframe) {
                HapticFeedback.selectionClick();
                setState(() {
                  selectedTimeframe = timeframe;
                });
                _animationController.reset();
                _animationController.forward();
              }
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? widget.primaryColor : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? widget.primaryColor : Colors.grey.withOpacity(0.3),
                ),
              ),
              child: Text(
                timeframe,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 📊 Build simple line chart
  Widget _buildSimpleChart(List<ChartPoint> points, double currentPrice) {
    if (points.length < 2) {
      return SizedBox(
        height: widget.height - 100,
        child: const Center(
          child: Text(
            'Insufficient data',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final minPrice = points.map((p) => p.price).reduce((a, b) => a < b ? a : b);
    final maxPrice = points.map((p) => p.price).reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;
    
    return Container(
      height: widget.height - 100,
      margin: const EdgeInsets.all(16),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return CustomPaint(
            size: Size.infinite,
            painter: SimpleChartPainter(
              points: points,
              minPrice: minPrice,
              maxPrice: maxPrice,
              primaryColor: widget.primaryColor,
              animation: _animation.value,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Price header
          Consumer<PriceProvider>(
            builder: (context, priceProvider, child) {
              final currentPrice = priceProvider.getPrice(widget.symbol) ?? 0.0;
              final priceChange = priceProvider.getPriceChange(widget.symbol) ?? 0.0;
              
              return Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '\$${NumberFormatter.formatDouble(currentPrice)}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: priceChange >= 0 
                              ? const Color(0xFF0BAB9B).withOpacity(0.1)
                              : const Color(0xFFF43672).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                priceChange >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                                size: 14,
                                color: priceChange >= 0 
                                  ? const Color(0xFF0BAB9B)
                                  : const Color(0xFFF43672),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${priceChange >= 0 ? '+' : ''}${priceChange.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: priceChange >= 0 
                                    ? const Color(0xFF0BAB9B)
                                    : const Color(0xFFF43672),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Last updated: ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          
          // Timeframe selector
          _buildTimeframeSelector(),
          
          // Chart area
          Consumer<PriceProvider>(
            builder: (context, priceProvider, child) {
              final currentPrice = priceProvider.getPrice(widget.symbol) ?? 100.0;
              final chartPoints = _generateChartData(currentPrice);
              
              return _buildSimpleChart(chartPoints, currentPrice);
            },
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Chart point data class
class ChartPoint {
  final DateTime timestamp;
  final double price;
  final double volume;

  ChartPoint({
    required this.timestamp,
    required this.price,
    required this.volume,
  });
}

/// Custom painter for simple chart
class SimpleChartPainter extends CustomPainter {
  final List<ChartPoint> points;
  final double minPrice;
  final double maxPrice;
  final Color primaryColor;
  final double animation;

  SimpleChartPainter({
    required this.points,
    required this.minPrice,
    required this.maxPrice,
    required this.primaryColor,
    required this.animation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = primaryColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withOpacity(0.3 * animation),
          primaryColor.withOpacity(0.05 * animation),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final gradientPath = Path();
    
    final priceRange = maxPrice - minPrice;
    if (priceRange <= 0) return;

    // Calculate points
    final chartPoints = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final y = size.height - ((points[i].price - minPrice) / priceRange) * size.height;
      chartPoints.add(Offset(x, y));
    }

    // Draw line with animation
    final animatedPointCount = (chartPoints.length * animation).round();
    if (animatedPointCount < 2) return;

    // Build path
    path.moveTo(chartPoints[0].dx, chartPoints[0].dy);
    gradientPath.moveTo(chartPoints[0].dx, size.height);
    gradientPath.lineTo(chartPoints[0].dx, chartPoints[0].dy);

    for (int i = 1; i < animatedPointCount; i++) {
      path.lineTo(chartPoints[i].dx, chartPoints[i].dy);
      gradientPath.lineTo(chartPoints[i].dx, chartPoints[i].dy);
    }

    // Close gradient path
    if (animatedPointCount > 0) {
      gradientPath.lineTo(chartPoints[animatedPointCount - 1].dx, size.height);
      gradientPath.close();
    }

    // Draw gradient area
    canvas.drawPath(gradientPath, gradientPaint);
    
    // Draw line
    canvas.drawPath(path, paint);

    // Draw points
    final pointPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < animatedPointCount; i++) {
      canvas.drawCircle(chartPoints[i], 4, pointPaint);
      canvas.drawCircle(chartPoints[i], 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
