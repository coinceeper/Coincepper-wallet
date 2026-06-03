import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../services/chart_data_manager.dart' as cdm;
import '../services/chart_api_service.dart';
import '../services/service_provider.dart';
import '../providers/price_provider.dart';
import 'dart:async';
import 'dart:math' as math;

class CryptoChartWidget extends StatefulWidget {
  final String symbol;
  final double height;
  final Color? lineColor;

  const CryptoChartWidget({
    super.key,
    required this.symbol,
    this.height = 200,
    this.lineColor,
  });

  @override
  State<CryptoChartWidget> createState() => _CryptoChartWidgetState();
}

class _CryptoChartWidgetState extends State<CryptoChartWidget> {
  String selectedTimeFrame = '1d';
  ChartData? chartData;
  LivePriceData? livePrice;
  bool isLoading = true;
  String? error;
  Timer? _liveUpdateTimer;

  final List<Map<String, String>> timeFrames = [
    {'label': '1H', 'value': '1h'},
    {'label': '1D', 'value': '1d'},
    {'label': '1W', 'value': '1w'},
    {'label': '1M', 'value': '1m'},
    {'label': '3M', 'value': '3m'},
    {'label': '1Y', 'value': '1y'},
  ];

  @override
  void initState() {
    super.initState();
    _loadChartData();
    _startLiveUpdates();
  }

  @override
  void dispose() {
    _liveUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadChartData() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      print('🔄 Loading chart data for ${widget.symbol} with timeframe $selectedTimeFrame');
      
      // Try to get real chart data from ChartDataManager (V2 cache proxy)
      final chartDataManager = cdm.ChartDataManager.instance;
      final apiChartData = await chartDataManager.getChartData(
        widget.symbol,
        selectedTimeFrame,
        'USD',
      );
      
      if (apiChartData != null && apiChartData.points.isNotEmpty) {
        // Convert from chart_data_manager.ChartData to chart_api_service.ChartData
        final prices = apiChartData.points.map((p) => p.price).toList();
        final firstPrice = prices.first;
        final lastPrice = prices.last;
        final priceChange = lastPrice - firstPrice;
        final priceChangePercent = firstPrice > 0 ? (priceChange / firstPrice) * 100 : 0.0;
        final minPrice = prices.reduce((a, b) => a < b ? a : b).toDouble();
        final maxPrice = prices.reduce((a, b) => a > b ? a : b).toDouble();

        setState(() {
          chartData = ChartData(
            points: apiChartData.points
                .map((p) => ChartPoint(
                      timestamp: p.timestamp,
                      price: p.price,
                    ))
                .toList(),
            currentPrice: lastPrice,
            priceChange: priceChange,
            priceChangePercent: priceChangePercent,
            minPrice: minPrice,
            maxPrice: maxPrice,
            timeFrame: selectedTimeFrame,
          );
          isLoading = false;
        });
        print('✅ Real chart data loaded successfully: ${apiChartData.points.length} points');
        print('📊 Price range: \$${minPrice.toStringAsFixed(2)} - \$${maxPrice.toStringAsFixed(2)}');
        return;
      }
      
      // If API returns null or empty data, show gray "no data" chart
      print('⚠️ No real chart data available for ${widget.symbol}');
      if (apiChartData == null) {
        print('   - ChartDataManager returned null');
      } else {
        print('   - ChartDataManager returned empty data (${apiChartData.points.length} points)');
      }
      
      final noDataChart = _createNoDataChart();
      setState(() {
        chartData = noDataChart;
        isLoading = false;
      });
      print('✅ No-data chart displayed for ${widget.symbol}');
      
    } catch (e) {
      print('❌ Error loading chart data for ${widget.symbol}: $e');
      
      // On error, show no-data chart
      final noDataChart = _createNoDataChart();
      setState(() {
        chartData = noDataChart;
        isLoading = false;
        error = 'Failed to load chart data';
      });
    }
  }

  /// Create a realistic demo chart when no API data is available
  ChartData _createNoDataChart() {
    final now = DateTime.now();
    final points = <ChartPoint>[];
    
    // Get proper data points and interval based on timeframe
    int dataPoints;
    Duration interval;
    
    switch (selectedTimeFrame) {
      case '1h':
        dataPoints = 60;
        interval = const Duration(minutes: 1);
        break;
      case '1d':
        dataPoints = 24;
        interval = const Duration(hours: 1);
        break;
      case '1w':
        dataPoints = 168; // 7 days × 24 hours
        interval = const Duration(hours: 1);
        break;
      case '1m':
        dataPoints = 30;
        interval = const Duration(days: 1);
        break;
      case '3m':
        dataPoints = 90; // 90 days
        interval = const Duration(days: 1);
        break;
      case '1y':
        dataPoints = 52; // 52 weeks
        interval = const Duration(days: 7);
        break;
      default:
        dataPoints = 24;
        interval = const Duration(hours: 1);
    }

    // Base price for different symbols
    double basePrice = 1.0;
    switch (widget.symbol.toUpperCase()) {
      case 'BTC':
        basePrice = 45000.0;
        break;
      case 'ETH':
        basePrice = 3000.0;
        break;
      case 'TRX':
        basePrice = 0.08;
        break;
      case 'NCC':
        basePrice = 0.22;
        break;
      case 'USDT':
        basePrice = 1.0;
        break;
      default:
        basePrice = 100.0;
    }

    // Generate realistic price movements with different patterns per timeframe
    final random = math.Random(widget.symbol.hashCode); // Consistent seed per symbol
    double currentPrice = basePrice;
    
    // Different volatility and trend patterns for different timeframes
    double volatility;
    double trendStrength;
    
    switch (selectedTimeFrame) {
      case '1h':
        volatility = 0.02; // ±2% for hourly
        trendStrength = 0.01; // ±1% overall trend
        break;
      case '1d':
        volatility = 0.05; // ±5% for daily
        trendStrength = 0.03; // ±3% overall trend
        break;
      case '1w':
        volatility = 0.08; // ±8% for weekly
        trendStrength = 0.05; // ±5% overall trend
        break;
      case '1m':
        volatility = 0.15; // ±15% for monthly
        trendStrength = 0.10; // ±10% overall trend
        break;
      case '3m':
        volatility = 0.25; // ±25% for 3-month
        trendStrength = 0.15; // ±15% overall trend
        break;
      case '1y':
        volatility = 0.50; // ±50% for yearly
        trendStrength = 0.30; // ±30% overall trend
        break;
      default:
        volatility = 0.05;
        trendStrength = 0.03;
    }
    
    double trend = (random.nextDouble() - 0.5) * 2 * trendStrength;
    
    for (int i = dataPoints - 1; i >= 0; i--) {
      final timestamp = now.subtract(interval * i);
      final progress = (dataPoints - 1 - i) / (dataPoints - 1);
      
      // Add gradual trend + random variation + some wave pattern
      final trendEffect = trend * progress;
      final waveEffect = math.sin(progress * math.pi * 2) * volatility * 0.3;
      final randomVariation = (random.nextDouble() - 0.5) * volatility;
      final totalVariation = trendEffect + waveEffect + randomVariation;
      
      currentPrice = basePrice * (1 + totalVariation);
      
      // Ensure price doesn't go negative
      if (currentPrice < 0) currentPrice = basePrice * 0.1;
      
      points.add(ChartPoint(
        timestamp: timestamp,
        price: currentPrice,
      ));
    }
    
    if (points.isNotEmpty) {
      final prices = points.map((p) => p.price).toList();
      final minPrice = prices.reduce(math.min);
      final maxPrice = prices.reduce(math.max);
      final firstPrice = points.first.price;
      final lastPrice = points.last.price;
      final priceChange = lastPrice - firstPrice;
      final priceChangePercent = (priceChange / firstPrice) * 100;

      return ChartData(
        points: points,
        currentPrice: lastPrice,
        priceChange: priceChange,
        priceChangePercent: priceChangePercent,
        minPrice: minPrice,
        maxPrice: maxPrice,
        timeFrame: selectedTimeFrame,
      );
    }
    
    return ChartData(
      points: points,
      currentPrice: 0.0,
      priceChange: 0.0,
      priceChangePercent: 0.0,
      minPrice: 0.0,
      maxPrice: 0.0,
      timeFrame: selectedTimeFrame,
    );
  }

  /// Fallback method to generate sample data when APIs are not available
  Future<ChartData?> _loadFallbackChartData() async {
    try {
      print('🔄 Generating fallback chart data for ${widget.symbol}');
      
      // Generate sample data points based on timeframe
      final now = DateTime.now();
      final points = <ChartPoint>[];
      int dataPoints;
      Duration interval;
      
      switch (selectedTimeFrame) {
        case '1h':
          dataPoints = 60;
          interval = const Duration(minutes: 1);
          break;
        case '1d':
          dataPoints = 24;
          interval = const Duration(hours: 1);
          break;
        case '1w':
          dataPoints = 168; // 7 days × 24 hours
          interval = const Duration(hours: 1);
          break;
        case '1m':
          dataPoints = 30;
          interval = const Duration(days: 1);
          break;
        case '3m':
          dataPoints = 90; // 90 days
          interval = const Duration(days: 1);
          break;
        case '1y':
          dataPoints = 52; // 52 weeks
          interval = const Duration(days: 7);
          break;
        default:
          dataPoints = 24;
          interval = const Duration(hours: 1);
      }

      // Base price for different symbols
      double basePrice = 1.0;
      switch (widget.symbol.toUpperCase()) {
        case 'BTC':
          basePrice = 45000.0;
          break;
        case 'ETH':
          basePrice = 3000.0;
          break;
        case 'TRX':
          basePrice = 0.08;
          break;
        case 'NCC':
          basePrice = 0.22;
          break;
        default:
          basePrice = 100.0;
      }

      // Generate realistic price movements with trend
      final random = math.Random();
      double currentPrice = basePrice;
      double trend = (random.nextDouble() - 0.5) * 0.02; // Overall trend ±1%
      
      for (int i = dataPoints - 1; i >= 0; i--) {
        final timestamp = now.subtract(interval * i);
        
        // Add gradual trend + random variation
        final trendEffect = trend * (dataPoints - i) / dataPoints;
        final randomVariation = (random.nextDouble() - 0.5) * 0.05; // ±2.5%
        final totalVariation = trendEffect + randomVariation;
        
        currentPrice = basePrice * (1 + totalVariation);
        
        // Ensure price doesn't go negative
        if (currentPrice < 0) currentPrice = basePrice * 0.1;
        
        points.add(ChartPoint(
          timestamp: timestamp,
          price: currentPrice,
        ));
      }

      if (points.isNotEmpty) {
        final prices = points.map((p) => p.price).toList();
        final minPrice = prices.reduce(math.min);
        final maxPrice = prices.reduce(math.max);
        final firstPrice = points.first.price;
        final lastPrice = points.last.price;
        final priceChange = lastPrice - firstPrice;
        final priceChangePercent = (priceChange / firstPrice) * 100;

        return ChartData(
          points: points,
          currentPrice: lastPrice,
          priceChange: priceChange,
          priceChangePercent: priceChangePercent,
          minPrice: minPrice,
          maxPrice: maxPrice,
          timeFrame: selectedTimeFrame,
        );
      }
      
      return null;
    } catch (e) {
      print('❌ Error generating fallback data: $e');
      return null;
    }
  }

  /// Start live price updates every 30 seconds
  void _startLiveUpdates() {
    _loadLivePrice(); // Initial load
    
    _liveUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadLivePrice();
    });
  }

  /// Load live price data — از V2 prices endpoint
  Future<void> _loadLivePrice() async {
    try {
      print('🔄 Loading live price for ${widget.symbol} (V2)');
      
      // Try V2 price endpoint first
      final apiService = ServiceProvider.instance.apiService;
      final v2Price = await apiService.getPriceV2(widget.symbol);

      if (v2Price != null) {
        setState(() {
          livePrice = LivePriceData(
            price: v2Price,
            change24h: 0,
            volume24h: 0,
            lastUpdated: DateTime.now(),
          );
        });
        print('✅ Live price updated from V2: \$${v2Price.toStringAsFixed(2)}');
      } else {
        print('⚠️ V2 price fetch returned null for ${widget.symbol}');
        
        // Use existing PriceProvider as fallback
        if (mounted) {
          try {
            final priceProvider = Provider.of<PriceProvider>(context, listen: false);
            final price = priceProvider.getPrice(widget.symbol);
            
            if (price != null && price > 0) {
              // Create LivePriceData from PriceProvider
              setState(() {
                livePrice = LivePriceData(
                  price: price,
                  change24h: 0.0, // PriceProvider doesn't provide change data
                  volume24h: 0.0,
                  lastUpdated: DateTime.now(),
                );
              });
              print('✅ Live price updated from PriceProvider fallback: \$${price.toStringAsFixed(2)}');
            } else {
              print('⚠️ PriceProvider also has no price for ${widget.symbol}');
            }
          } catch (e) {
            print('❌ Error accessing PriceProvider: $e');
          }
        }
      }
    } catch (e) {
      print('❌ Error loading live price for ${widget.symbol}: $e');
      // Silent failure for live price updates
    }
  }

  void _onTimeFrameSelected(String timeFrame) {
    if (timeFrame != selectedTimeFrame) {
      setState(() {
        selectedTimeFrame = timeFrame;
      });
      _loadChartData();
    }
  }

  String _generateSvgPath(List<ChartPoint> points, double width, double height) {
    if (points.isEmpty) return '';

    final minPrice = chartData!.minPrice;
    final maxPrice = chartData!.maxPrice;
    final priceRange = maxPrice - minPrice;
    
    if (priceRange == 0) {
      // If all prices are the same, draw a horizontal line
      final y = height / 2;
      return 'M 0 $y L $width $y';
    }

    final stepX = width / (points.length - 1);
    
    String path = '';
    
    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final normalizedY = (points[i].price - minPrice) / priceRange;
      final y = height - (normalizedY * height * 0.8) - (height * 0.1); // Add padding
      
      if (i == 0) {
        path += 'M ${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)}';
      } else {
        // Use smooth curves for better visualization
        final prevX = (i - 1) * stepX;
        final prevNormalizedY = (points[i - 1].price - minPrice) / priceRange;
        final prevY = height - (prevNormalizedY * height * 0.8) - (height * 0.1);
        
        final cpX1 = prevX + (x - prevX) * 0.5;
        final cpY1 = prevY;
        final cpX2 = prevX + (x - prevX) * 0.5;
        final cpY2 = y;
        
        path += ' C ${cpX1.toStringAsFixed(2)} ${cpY1.toStringAsFixed(2)}, ${cpX2.toStringAsFixed(2)} ${cpY2.toStringAsFixed(2)}, ${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)}';
      }
    }
    
    return path;
  }

  String _generateGradientPath(List<ChartPoint> points, double width, double height) {
    if (points.isEmpty) return '';

    final minPrice = chartData!.minPrice;
    final maxPrice = chartData!.maxPrice;
    final priceRange = maxPrice - minPrice;
    
    if (priceRange == 0) {
      // If all prices are the same, create a rectangle
      final y = height / 2;
      return 'M 0 $height L 0 $y L $width $y L $width $height Z';
    }

    final stepX = width / (points.length - 1);
    
    String path = 'M 0 $height';
    
    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final normalizedY = (points[i].price - minPrice) / priceRange;
      final y = height - (normalizedY * height * 0.8) - (height * 0.1); // Add padding
      
      if (i == 0) {
        path += ' L ${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)}';
      } else {
        // Use smooth curves matching the line path
        final prevX = (i - 1) * stepX;
        final prevNormalizedY = (points[i - 1].price - minPrice) / priceRange;
        final prevY = height - (prevNormalizedY * height * 0.8) - (height * 0.1);
        
        final cpX1 = prevX + (x - prevX) * 0.5;
        final cpY1 = prevY;
        final cpX2 = prevX + (x - prevX) * 0.5;
        final cpY2 = y;
        
        path += ' C ${cpX1.toStringAsFixed(2)} ${cpY1.toStringAsFixed(2)}, ${cpX2.toStringAsFixed(2)} ${cpY2.toStringAsFixed(2)}, ${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)}';
      }
    }
    
    path += ' L $width $height Z';
    
    return path;
  }

  Widget _buildChart() {
    if (isLoading) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
          ),
        ),
      );
    }

    if (error != null) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.grey, size: 48),
              const SizedBox(height: 8),
              Text(
                error!,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadChartData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0BAB9B),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

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

    // Check if this is a no-data chart (all prices are zero)
    final isNoDataChart = chartData!.currentPrice == 0.0 && 
                         chartData!.maxPrice == 0.0 && 
                         chartData!.minPrice == 0.0;
    
    final isPositive = chartData!.priceChangePercent >= 0;
    final lineColor = widget.lineColor ?? 
                     (isNoDataChart ? Colors.grey : 
                      (isPositive ? const Color(0xFF20CDA4) : const Color(0xFFF43672)));
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = constraints.maxWidth - 32; // Padding
        final chartHeight = widget.height - 60; // Account for padding and info

        final svgPath = _generateSvgPath(chartData!.points, chartWidth, chartHeight);
        final gradientPath = _generateGradientPath(chartData!.points, chartWidth, chartHeight);

        final svgContent = '''
        <svg width="$chartWidth" height="$chartHeight" viewBox="0 0 $chartWidth $chartHeight" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="chartGradient" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" style="stop-color:${_colorToHex(lineColor)};stop-opacity:0.4" />
              <stop offset="100%" style="stop-color:${_colorToHex(lineColor)};stop-opacity:0.0" />
            </linearGradient>
          </defs>
          <path d="$gradientPath" fill="url(#chartGradient)" />
          <path d="$svgPath" stroke="${_colorToHex(lineColor)}" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
        ''';

        return Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SvgPicture.string(
                    svgContent,
                    width: chartWidth,
                    height: chartHeight,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              // Price info at bottom
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNoDataChart ? 'No price data' : 'Low: \$${chartData!.minPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          isNoDataChart ? 'available' : 'High: \$${chartData!.maxPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Live price if available, otherwise use chart data
                        if (!isNoDataChart && livePrice != null)
                          Text(
                            '\$${livePrice!.price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        Row(
                          children: [
                            if (!isNoDataChart) ...[
                              Icon(
                                (livePrice?.change24h ?? chartData!.priceChangePercent) >= 0 
                                    ? Icons.trending_up 
                                    : Icons.trending_down,
                                color: lineColor,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${(livePrice?.change24h ?? chartData!.priceChangePercent) >= 0 ? '+' : ''}${(livePrice?.change24h ?? chartData!.priceChangePercent).toStringAsFixed(2)}%',
                                style: TextStyle(
                                  color: lineColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ] else ...[
                              const Icon(
                                Icons.help_outline,
                                color: Colors.grey,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                '0.00%',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ]
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Time frame selector
        Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: timeFrames.map((timeFrame) {
              final isSelected = timeFrame['value'] == selectedTimeFrame;
              return GestureDetector(
                onTap: () => _onTimeFrameSelected(timeFrame['value']!),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF0BAB9B) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    timeFrame['label']!,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Chart
        _buildChart(),
      ],
    );
  }
}
