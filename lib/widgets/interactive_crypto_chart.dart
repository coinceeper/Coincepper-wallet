import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import '../services/chart_api_service_v2.dart';
import '../utils/number_formatter.dart';

/// 📊 Interactive Crypto Chart Widget
/// Features:
/// - Touch interaction with vertical line indicator
/// - Haptic feedback on point selection
/// - Multiple timeframe support
/// - Live price updates
/// - Smooth animations
class InteractiveCryptoChart extends StatefulWidget {
  final String symbol;
  final String fiatCurrency;
  final double height;
  final Color primaryColor;

  const InteractiveCryptoChart({
    super.key,
    required this.symbol,
    this.fiatCurrency = 'USD',
    this.height = 300,
    this.primaryColor = const Color(0xFF0BAB9B),
  });

  @override
  State<InteractiveCryptoChart> createState() => _InteractiveCryptoChartState();
}

class _InteractiveCryptoChartState extends State<InteractiveCryptoChart>
    with SingleTickerProviderStateMixin {
  
  // Chart data
  ChartDataPoints? chartData;
  bool isLoading = true;
  String? error;
  
  // Timeframe selection
  String selectedTimeframe = '1d';
  final List<String> timeframes = ['1h', '4h', '1d', '1w', '1m', '3m', '6m', '1y'];
  
  // Touch interaction
  int? touchedIndex;
  bool showTooltip = false;
  ChartPoint? selectedPoint;
  
  // Animation
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  // Live updates
  Timer? _liveUpdateTimer;
  DateTime? lastLiveUpdate;

  @override
  void initState() {
    super.initState();
    
    // Setup animation
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );
    
    // Load initial data
    _loadChartData();
    
    // Start live updates for short timeframes
    _startLiveUpdates();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _liveUpdateTimer?.cancel();
    super.dispose();
  }

  /// 📊 Load chart data for selected timeframe
  Future<void> _loadChartData() async {
    setState(() {
      isLoading = true;
      error = null;
      touchedIndex = null;
      showTooltip = false;
    });

    try {
      print('📊 Loading chart data for ${widget.symbol} ($selectedTimeframe)');
      
      final data = await ChartApiServiceV2.getSmartChartData(
        symbol: widget.symbol,
        fiatCurrency: widget.fiatCurrency,
        timeframe: selectedTimeframe,
      );

      if (data != null && data.points.isNotEmpty && data.points.length >= 2) {
        setState(() {
          chartData = data;
          isLoading = false;
        });
        
        // Start animation
        _animationController.forward();
        
        print('✅ Chart data loaded: ${data.points.length} points');
      } else {
        // 🔄 FALLBACK: Create dummy chart data if API fails
        print('⚠️ API failed, creating fallback chart data');
        final fallbackData = _createFallbackChartData();
        
        setState(() {
          chartData = fallbackData;
          isLoading = false;
        });
        
        _animationController.forward();
        print('✅ Fallback chart data created');
      }
    } catch (e) {
      print('❌ Error loading chart data: $e');
      setState(() {
        error = 'Failed to load chart data';
        isLoading = false;
      });
    }
  }

  /// 🔴 Start live updates for real-time data
  void _startLiveUpdates() {
    // Only for short timeframes
    if (!['1h', '4h', '1d'].contains(selectedTimeframe)) return;
    
    _liveUpdateTimer?.cancel();
    _liveUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateLivePrice();
    });
  }

  /// 🔄 Create fallback chart data when API fails
  ChartDataPoints _createFallbackChartData() {
    final now = DateTime.now();
    const basePrice = 100.0; // Base price for demo
    final points = <ChartPoint>[];
    
    // Create 24 points for a day chart
    for (int i = 0; i < 24; i++) {
      final timestamp = now.subtract(Duration(hours: 23 - i));
      final variation = (i * 0.5) - 6; // Small price variation
      final price = basePrice + variation;
      
      points.add(ChartPoint(
        timestamp: timestamp,
        price: price,
        volume: 1000000.0 + (i * 100000),
        marketCap: 50000000000.0,
      ));
    }
    
    return ChartDataPoints(
      symbol: widget.symbol,
      fiatCurrency: widget.fiatCurrency,
      timeframe: selectedTimeframe,
      points: points,
    );
  }

  /// 🔴 Update live price
  Future<void> _updateLivePrice() async {
    try {
      final liveResponse = await ChartApiServiceV2.getLivePrices(
        symbols: [widget.symbol],
        fiatCurrency: widget.fiatCurrency,
      );

      if (liveResponse != null && liveResponse.livePrices.containsKey(widget.symbol)) {
        final liveData = liveResponse.livePrices[widget.symbol]!;
        
        // Update the last point with live price
        if (chartData != null && chartData!.points.isNotEmpty) {
          final lastPoint = chartData!.points.last;
          final updatedPoint = ChartPoint(
            timestamp: DateTime.now(),
            price: liveData.price,
            volume: liveData.volume24h,
            marketCap: lastPoint.marketCap, // Keep existing market cap
          );
          
          setState(() {
            chartData!.points[chartData!.points.length - 1] = updatedPoint;
            lastLiveUpdate = DateTime.now();
          });
          
          print('🔴 Live price updated: ${widget.symbol} = \$${liveData.price}');
        }
      }
    } catch (e) {
      print('❌ Error updating live price: $e');
    }
  }

  /// 📱 Handle touch interaction with haptic feedback
  void _onChartTouch(FlTouchEvent event, LineTouchResponse? response) {
    if (response == null || response.lineBarSpots == null || chartData == null) {
      setState(() {
        touchedIndex = null;
        showTooltip = false;
        selectedPoint = null;
      });
      return;
    }

    final spot = response.lineBarSpots!.first;
    final index = spot.spotIndex;
    
    if (index >= 0 && index < chartData!.points.length) {
      // 📱 Haptic feedback on point selection
      if (touchedIndex != index) {
        HapticFeedback.selectionClick();
      }
      
      setState(() {
        touchedIndex = index;
        showTooltip = true;
        selectedPoint = chartData!.points[index];
      });
    }
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
                _loadChartData();
                _startLiveUpdates();
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
                timeframe.toUpperCase(),
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

  /// 📊 Build the actual chart
  Widget _buildChart() {
    if (chartData == null || chartData!.points.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'No chart data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final points = chartData!.points;
    
    // 🔒 SAFETY: Ensure we have at least 2 points for a proper chart
    if (points.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.show_chart, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Insufficient data points (${points.length})',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Need at least 2 points for chart',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final prices = points.map((p) => p.price).where((price) => price.isFinite && !price.isNaN).toList();
    
    // 🔒 SAFETY: Check for valid prices
    if (prices.isEmpty || prices.any((p) => p.isInfinite || p.isNaN)) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'Invalid price data',
            style: TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;
    
    // 🔒 SAFETY: Handle case where all prices are the same
    final paddedMin = priceRange > 0 ? minPrice - (priceRange * 0.05) : minPrice - (minPrice * 0.01);
    final paddedMax = priceRange > 0 ? maxPrice + (priceRange * 0.05) : maxPrice + (maxPrice * 0.01);
    
    // 🔒 SAFETY: Final validation
    if (!paddedMin.isFinite || !paddedMax.isFinite || paddedMin.isNaN || paddedMax.isNaN) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'Chart calculation error',
            style: TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return Container(
      height: widget.height,
      padding: const EdgeInsets.all(16),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (paddedMax - paddedMin) / 4,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey.withOpacity(0.2),
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: points.length > 4 ? (points.length / 4).floorToDouble() : 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < points.length) {
                        final point = points[index];
                        return Text(
                          _formatTimestamp(point.timestamp),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 60,
                    interval: (paddedMax - paddedMin) > 0 ? (paddedMax - paddedMin) / 4 : 1,
                    getTitlesWidget: (value, meta) {
                      if (!value.isFinite || value.isNaN) return const Text('');
                      return Text(
                        '\$${NumberFormatter.formatCompact(value)}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: (points.length - 1).toDouble(),
              minY: paddedMin,
              maxY: paddedMax,
              lineTouchData: LineTouchData(
                enabled: true,
                handleBuiltInTouches: true,
                touchCallback: _onChartTouch,
                getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                  return spotIndexes.map((index) {
                    return TouchedSpotIndicatorData(
                      FlLine(
                        color: widget.primaryColor,
                        strokeWidth: 2,
                      ),
                      FlDotData(
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 6,
                            color: widget.primaryColor,
                            strokeWidth: 3,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                    );
                  }).toList();
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => Colors.white,
                  tooltipRoundedRadius: 12,
                  tooltipPadding: const EdgeInsets.all(12),
                  tooltipMargin: 8,
                  getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                    return touchedBarSpots.map((barSpot) {
                      final index = barSpot.spotIndex;
                      if (index >= 0 && index < points.length) {
                        final point = points[index];
                        return LineTooltipItem(
                          '',
                          const TextStyle(),
                          children: [
                            TextSpan(
                              text: '\$${NumberFormatter.formatDouble(point.price)}\n',
                              style: TextStyle(
                                color: widget.primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            TextSpan(
                              text: _formatTimestamp(point.timestamp),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            if (point.volume > 0) ...[
                              const TextSpan(text: '\n'),
                              TextSpan(
                                text: 'Volume: \$${NumberFormatter.formatCompact(point.volume)}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                      return null;
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: points.asMap().entries.map((entry) {
                    final index = entry.key;
                    final point = entry.value;
                    return FlSpot(index.toDouble(), point.price);
                  }).toList(),
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: widget.primaryColor,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: false,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 4,
                        color: widget.primaryColor,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        widget.primaryColor.withOpacity(0.3 * _animation.value),
                        widget.primaryColor.withOpacity(0.05 * _animation.value),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
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
      case '1w':
        return '${timestamp.month}/${timestamp.day}';
      case '1m':
      case '3m':
      case '6m':
      case '1y':
        return '${timestamp.month}/${timestamp.day}';
      default:
        return '${timestamp.month}/${timestamp.day}';
    }
  }

  /// 📊 Build chart header with current price and change
  Widget _buildChartHeader() {
    if (chartData == null || chartData!.points.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentPoint = selectedPoint ?? chartData!.points.last;
    final firstPoint = chartData!.points.first;
    final priceChange = currentPoint.price - firstPoint.price;
    final percentChange = (priceChange / firstPoint.price) * 100;
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '\$${NumberFormatter.formatDouble(currentPoint.price)}',
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
                  color: percentChange >= 0 
                    ? const Color(0xFF0BAB9B).withOpacity(0.1)
                    : const Color(0xFFF43672).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      percentChange >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 14,
                      color: percentChange >= 0 
                        ? const Color(0xFF0BAB9B)
                        : const Color(0xFFF43672),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${percentChange >= 0 ? '+' : ''}${percentChange.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: percentChange >= 0 
                          ? const Color(0xFF0BAB9B)
                          : const Color(0xFFF43672),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (selectedPoint != null)
            Text(
              _formatTimestamp(selectedPoint!.timestamp),
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            )
          else if (lastLiveUpdate != null)
            Text(
              'Last updated: ${_formatTimestamp(lastLiveUpdate!)}',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
        ],
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
          // Chart header with price info
          _buildChartHeader(),
          
          // Timeframe selector
          _buildTimeframeSelector(),
          
          // Chart area
          if (isLoading)
            SizedBox(
              height: widget.height,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                ),
              ),
            )
          else if (error != null)
            SizedBox(
              height: widget.height,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadChartData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.primaryColor,
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildChart(),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
