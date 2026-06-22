import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/coinmarketcap_service 2.dart';

class PriceChartWidget extends StatefulWidget {
  final String symbol;
  final String selectedTimeRange;
  final Color lineColor;
  final double currentPrice;

  const PriceChartWidget({
    super.key,
    required this.symbol,
    required this.selectedTimeRange,
    this.lineColor = const Color(0xFFE53E3E),
    required this.currentPrice,
  });

  @override
  State<PriceChartWidget> createState() => _PriceChartWidgetState();
}

class _PriceChartWidgetState extends State<PriceChartWidget> {
  List<ChartDataPoint> chartData = [];
  bool isLoading = true;
  final CoinMarketCapService _cmcService = CoinMarketCapService();

  @override
  void initState() {
    super.initState();
    _loadChartData();
  }

  @override
  void didUpdateWidget(PriceChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTimeRange != widget.selectedTimeRange ||
        oldWidget.symbol != widget.symbol) {
      _loadChartData();
    }
  }

  Future<void> _loadChartData() async {
    setState(() {
      isLoading = true;
    });

    try {
      final data = await _cmcService.getHistoricalData(
        widget.symbol,
        widget.selectedTimeRange,
      );

      if (data != null && data.isNotEmpty) {
        setState(() {
          chartData = data;
          isLoading = false;
        });
      } else {
        // Use mock data if API fails
        setState(() {
          chartData = _generateMockData();
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading chart data: $e');
      setState(() {
        chartData = _generateMockData();
        isLoading = false;
      });
    }
  }

  List<ChartDataPoint> _generateMockData() {
    final now = DateTime.now();
    final List<ChartDataPoint> points = [];
    
    int dataPoints;
    Duration interval;
    
    switch (widget.selectedTimeRange) {
      case '1H':
        dataPoints = 12;
        interval = const Duration(minutes: 5);
        break;
      case '1D':
        dataPoints = 24;
        interval = const Duration(hours: 1);
        break;
      case '1W':
        dataPoints = 7;
        interval = const Duration(days: 1);
        break;
      case '1M':
        dataPoints = 30;
        interval = const Duration(days: 1);
        break;
      case '1Y':
        dataPoints = 52;
        interval = const Duration(days: 7);
        break;
      default:
        dataPoints = 24;
        interval = const Duration(hours: 1);
    }
    
    double basePrice = widget.currentPrice > 0 ? widget.currentPrice : 851.03;
    
    for (int i = 0; i < dataPoints; i++) {
      final timestamp = now.subtract(interval * (dataPoints - 1 - i));
      
      // Create a more realistic price movement
      final progress = i / dataPoints;
      final trend = -0.1 + (progress * 0.2); // Overall slight downward trend
      final wave = 0.05 * (1 - 2 * progress) * (1 - 2 * progress); // Parabolic wave
      final noise = (i.hashCode % 200 - 100) / 10000; // Small random variation
      
      final priceMultiplier = 1 + trend + wave + noise;
      final price = basePrice * priceMultiplier;
      
      points.add(ChartDataPoint(
        timestamp: timestamp,
        price: price,
        volume: 1000000.0, // Default volume
      ));
    }
    
    return points;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFE53E3E),
          ),
        ),
      );
    }

    if (chartData.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No chart data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // Convert data to FlSpot for fl_chart
    final spots = chartData.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.price);
    }).toList();

    // Calculate min and max values for better chart scaling
    final prices = chartData.map((e) => e.price).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;
    final padding = priceRange * 0.1; // 10% padding

    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(
            show: false,
          ),
          titlesData: const FlTitlesData(
            show: false,
          ),
          borderData: FlBorderData(
            show: false,
          ),
          minX: 0,
          maxX: (chartData.length - 1).toDouble(),
          minY: minPrice - padding,
          maxY: maxPrice + padding,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: widget.lineColor,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(
                show: false,
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    widget.lineColor.withOpacity(0.3),
                    widget.lineColor.withOpacity(0.1),
                    widget.lineColor.withOpacity(0.05),
                  ],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                return touchedBarSpots.map((barSpot) {
                  final dataPoint = chartData[barSpot.x.toInt()];
                  return LineTooltipItem(
                    '\$${dataPoint.price.toStringAsFixed(2)}',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}

class TimeRangeSelector extends StatelessWidget {
  final String selectedRange;
  final Function(String) onRangeSelected;

  const TimeRangeSelector({
    super.key,
    required this.selectedRange,
    required this.onRangeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final ranges = ['1H', '1D', '1W', '1M', '1Y', 'All'];

    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: ranges.map((range) {
          final isSelected = range == selectedRange;
          return GestureDetector(
            onTap: () => onRangeSelected(range),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.grey.shade200 : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                range,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.black : Colors.grey,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
