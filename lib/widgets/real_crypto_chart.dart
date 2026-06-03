import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/number_formatter.dart';

/// 📊 Real Crypto Chart Widget
/// Uses actual coinceeper.com APIs for accurate chart data
class RealCryptoChart extends StatefulWidget {
  final String symbol;
  final double height;
  final Color primaryColor;

  const RealCryptoChart({
    super.key,
    required this.symbol,
    this.height = 300,
    this.primaryColor = const Color(0xFF0BAB9B),
  });

  @override
  State<RealCryptoChart> createState() => _RealCryptoChartState();
}

class _RealCryptoChartState extends State<RealCryptoChart>
    with SingleTickerProviderStateMixin {
  
  String selectedTimeframe = '1d';
  final List<Map<String, String>> timeframes = [
    {'key': '1h', 'label': '1H'},
    {'key': '4h', 'label': '4H'},
    {'key': '1d', 'label': '1D'},
    {'key': '1w', 'label': '1W'},
    {'key': '1m', 'label': '1M'},
    {'key': '3m', 'label': '3M'},
  ];
  
  List<RealChartPoint> chartPoints = [];
  bool isLoading = true;
  String? error;
  
  // Touch interaction
  int? selectedPointIndex;
  RealChartPoint? selectedPoint;
  
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
    
    _loadChartData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// 📊 Load chart data from real APIs
  Future<void> _loadChartData() async {
    setState(() {
      isLoading = true;
      error = null;
      selectedPointIndex = null;
      selectedPoint = null;
    });

    try {
      print('📊 RealCryptoChart: Loading data for ${widget.symbol} ($selectedTimeframe)');
      
      List<RealChartPoint> points = [];
      
      // Use appropriate API based on timeframe
      if (['1h', '4h', '1d', '1w'].contains(selectedTimeframe)) {
        // Use chart-data API for short timeframes
        points = await _getChartDataFromAPI();
      } else {
        // Use historical-prices API for long timeframes (1m, 3m)
        points = await _getHistoricalDataFromAPI();
      }
      
      if (points.isNotEmpty) {
        setState(() {
          chartPoints = points;
          isLoading = false;
        });
        
        _animationController.forward();
        print('✅ RealCryptoChart: Loaded ${points.length} real data points');
      } else {
        setState(() {
          error = 'No chart data available for ${widget.symbol}';
          isLoading = false;
        });
      }
    } catch (e) {
      print('❌ RealCryptoChart: Error loading data: $e');
      setState(() {
        error = 'Failed to load chart data: $e';
        isLoading = false;
      });
    }
  }

  /// 📈 Get data from chart-data API (for 1h, 4h, 1d, 1w)
  Future<List<RealChartPoint>> _getChartDataFromAPI() async {
    try {
      final pointsMap = {
        '1h': 60,
        '4h': 24, 
        '1d': 24,
        '1w': 168,
      };
      
      final response = await http.post(
        Uri.parse('https://coinceeper.com/api/chart-data'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'Symbol': widget.symbol,
          'FiatCurrency': 'USD',
          'timeframe': selectedTimeframe,
          'points': pointsMap[selectedTimeframe] ?? 24,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['chart_data'] != null) {
          final chartData = data['chart_data'];
          final dataPoints = chartData['data'] as List<dynamic>;
          
          return dataPoints.map((point) => RealChartPoint(
            timestamp: DateTime.parse(point['timestamp']),
            price: (point['price'] ?? 0).toDouble(),
            volume: (point['volume_24h'] ?? 0).toDouble(),
            marketCap: (point['market_cap'] ?? 0).toDouble(),
            change1h: (point['change_1h'] ?? 0).toDouble(),
            change24h: (point['change_24h'] ?? 0).toDouble(),
            change7d: (point['change_7d'] ?? 0).toDouble(),
          )).toList();
        }
      }
      
      print('❌ chart-data API failed: ${response.statusCode}');
      return [];
    } catch (e) {
      print('❌ Error calling chart-data API: $e');
      return [];
    }
  }

  /// 📊 Get data from historical-prices API (for 1m, 3m)
  Future<List<RealChartPoint>> _getHistoricalDataFromAPI() async {
    try {
      final now = DateTime.now();
      DateTime startTime;
      
      switch (selectedTimeframe) {
        case '1m':
          startTime = now.subtract(const Duration(days: 30));
          break;
        case '3m':
          startTime = now.subtract(const Duration(days: 90));
          break;
        default:
          startTime = now.subtract(const Duration(days: 7));
      }
      
      final response = await http.post(
        Uri.parse('https://coinceeper.com/api/historical-prices'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'Symbol': [widget.symbol],
          'FiatCurrencies': ['USD'],
          'time_start': startTime.toIso8601String(),
          'time_end': now.toIso8601String(),
          'interval': 'daily',
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['historical_data'] != null) {
          final historicalData = data['historical_data'];
          final symbolData = historicalData[widget.symbol];
          if (symbolData != null) {
            final usdData = symbolData['USD'];
            if (usdData != null) {
              final prices = List<double>.from(usdData['prices']);
              final timestamps = List<String>.from(usdData['timestamps']);
              final marketCaps = List<double>.from(usdData['market_caps']);
              final volumes = List<double>.from(usdData['volumes']);
              
              final points = <RealChartPoint>[];
              for (int i = 0; i < prices.length && i < timestamps.length; i++) {
                points.add(RealChartPoint(
                  timestamp: DateTime.parse(timestamps[i]),
                  price: prices[i],
                  volume: i < volumes.length ? volumes[i] : 0,
                  marketCap: i < marketCaps.length ? marketCaps[i] : 0,
                  change1h: 0, // Not available in historical data
                  change24h: 0,
                  change7d: 0,
                ));
              }
              
              return points;
            }
          }
        }
      }
      
      print('❌ historical-prices API failed: ${response.statusCode}');
      return [];
    } catch (e) {
      print('❌ Error calling historical-prices API: $e');
      return [];
    }
  }

  /// 🎨 Build timeframe selector
  Widget _buildTimeframeSelector() {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: timeframes.map((timeframe) {
          final isSelected = timeframe['key'] == selectedTimeframe;
          
          return GestureDetector(
            onTap: () {
              if (timeframe['key'] != selectedTimeframe) {
                HapticFeedback.selectionClick();
                setState(() {
                  selectedTimeframe = timeframe['key']!;
                  selectedPointIndex = null;
                  selectedPoint = null;
                });
                _animationController.reset();
                _loadChartData();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? widget.primaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? widget.primaryColor : Colors.grey.withOpacity(0.3),
                ),
              ),
              child: Text(
                timeframe['label']!,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 📊 Build real chart with interaction
  Widget _buildRealChart() {
    if (chartPoints.length < 2) {
      return SizedBox(
        height: widget.height - 80,
        child: const Center(
          child: Text(
            'Insufficient data points',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Container(
      height: widget.height - 80,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return GestureDetector(
            onPanUpdate: (details) => _handleChartTouch(details.localPosition),
            onTapDown: (details) => _handleChartTouch(details.localPosition),
            child: CustomPaint(
              size: Size.infinite,
              painter: RealChartPainter(
                points: chartPoints,
                primaryColor: widget.primaryColor,
                animation: _animation.value,
                selectedIndex: selectedPointIndex,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 📱 Handle chart touch interaction (like Trust Wallet)
  void _handleChartTouch(Offset localPosition) {
    if (chartPoints.isEmpty) return;
    
    final chartWidth = MediaQuery.of(context).size.width - 32;
    final pointSpacing = chartWidth / (chartPoints.length - 1);
    final touchedIndex = (localPosition.dx / pointSpacing).round();
    
    if (touchedIndex >= 0 && touchedIndex < chartPoints.length) {
      if (selectedPointIndex != touchedIndex) {
        HapticFeedback.selectionClick(); // ویبره مثل Trust Wallet
        setState(() {
          selectedPointIndex = touchedIndex;
          selectedPoint = chartPoints[touchedIndex];
        });
      }
    }
  }

  /// 📊 Build selected point info (exactly like Trust Wallet)
  Widget _buildSelectedPointInfo() {
    if (selectedPoint == null) {
      return const SizedBox(height: 40); // Reserve space
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _formatTimestamp(selectedPoint!.timestamp),
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            '\$${NumberFormatter.formatDouble(selectedPoint!.price)}',
            style: TextStyle(
              fontSize: 16,
              color: widget.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 🕐 Format timestamp based on timeframe
  String _formatTimestamp(DateTime timestamp) {
    switch (selectedTimeframe) {
      case '1h':
      case '4h':
        return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
      case '1d':
        return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
      case '1w':
      case '1m':
      case '3m':
        return '${timestamp.day}/${timestamp.month}';
      default:
        return '${timestamp.hour}:${timestamp.minute}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeframe selector
          _buildTimeframeSelector(),
          
          // Chart area
          if (isLoading)
            SizedBox(
              height: widget.height - 80,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                ),
              ),
            )
          else if (error != null)
            SizedBox(
              height: widget.height - 80,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadChartData,
                      style: ElevatedButton.styleFrom(backgroundColor: widget.primaryColor),
                      child: const Text('Retry', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildRealChart(),
          
          // Selected point info
          _buildSelectedPointInfo(),
        ],
      ),
    );
  }
}

/// Real chart point with all API data
class RealChartPoint {
  final DateTime timestamp;
  final double price;
  final double volume;
  final double marketCap;
  final double change1h;
  final double change24h;
  final double change7d;

  RealChartPoint({
    required this.timestamp,
    required this.price,
    required this.volume,
    required this.marketCap,
    required this.change1h,
    required this.change24h,
    required this.change7d,
  });
}

/// Real chart painter using actual API data
class RealChartPainter extends CustomPainter {
  final List<RealChartPoint> points;
  final Color primaryColor;
  final double animation;
  final int? selectedIndex;

  RealChartPainter({
    required this.points,
    required this.primaryColor,
    required this.animation,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final prices = points.map((p) => p.price).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;
    
    if (priceRange <= 0) return;

    // Paint for line
    final linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Paint for gradient area
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withOpacity(0.3 * animation),
          primaryColor.withOpacity(0.05 * animation),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Calculate chart points
    final chartPoints = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final y = size.height - ((points[i].price - minPrice) / priceRange) * size.height;
      chartPoints.add(Offset(x, y));
    }

    // Build paths with animation
    final animatedPointCount = (chartPoints.length * animation).round().clamp(2, chartPoints.length);
    
    final path = Path();
    final gradientPath = Path();
    
    // Start paths
    path.moveTo(chartPoints[0].dx, chartPoints[0].dy);
    gradientPath.moveTo(chartPoints[0].dx, size.height);
    gradientPath.lineTo(chartPoints[0].dx, chartPoints[0].dy);

    // Build smooth curve
    for (int i = 1; i < animatedPointCount; i++) {
      path.lineTo(chartPoints[i].dx, chartPoints[i].dy);
      gradientPath.lineTo(chartPoints[i].dx, chartPoints[i].dy);
    }

    // Close gradient path
    gradientPath.lineTo(chartPoints[animatedPointCount - 1].dx, size.height);
    gradientPath.close();

    // Draw gradient area
    canvas.drawPath(gradientPath, gradientPaint);
    
    // Draw main line
    canvas.drawPath(path, linePaint);

    // Draw interaction points
    final pointPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    final pointBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw all points (small)
    for (int i = 0; i < animatedPointCount; i++) {
      canvas.drawCircle(chartPoints[i], 3, pointBorderPaint);
      canvas.drawCircle(chartPoints[i], 2, pointPaint);
    }

    // Draw selected point (larger) + vertical line like Trust Wallet
    if (selectedIndex != null && selectedIndex! < animatedPointCount) {
      final selectedPoint = chartPoints[selectedIndex!];
      
      // Draw vertical dashed line (like Trust Wallet)
      final dashPaint = Paint()
        ..color = primaryColor.withOpacity(0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      
      // Draw dashed vertical line
      const dashHeight = 10.0;
      const dashSpace = 5.0;
      double currentY = 0;
      
      while (currentY < size.height) {
        canvas.drawLine(
          Offset(selectedPoint.dx, currentY),
          Offset(selectedPoint.dx, currentY + dashHeight),
          dashPaint,
        );
        currentY += dashHeight + dashSpace;
      }
      
      // Draw larger selected point
      canvas.drawCircle(selectedPoint, 8, pointBorderPaint);
      canvas.drawCircle(selectedPoint, 6, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
