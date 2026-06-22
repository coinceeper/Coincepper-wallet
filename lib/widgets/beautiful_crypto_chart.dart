import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import '../models/chart_models.dart';
import '../services/chart_data_service.dart';

/// 📊 Beautiful Crypto Chart Widget
/// A professional, reliable chart with multiple data sources and beautiful animations
class BeautifulCryptoChart extends StatefulWidget {
  final String symbol;
  final double height;
  final Color primaryColor;
  final Color backgroundColor;
  final bool showTimeframeSelector;
  final String initialTimeframe;
  final Function(ChartDataPoint? point, bool isPriceDown)? onPointSelected;
  final Function()? onPointDeselected;

  const BeautifulCryptoChart({
    super.key,
    required this.symbol,
    this.height = 300,
    this.primaryColor = const Color(0xFF0BAB9B),
    this.backgroundColor = Colors.white,
    this.showTimeframeSelector = true,
    this.initialTimeframe = '1d',
    this.onPointSelected,
    this.onPointDeselected,
  });

  @override
  State<BeautifulCryptoChart> createState() => _BeautifulCryptoChartState();
}

class _BeautifulCryptoChartState extends State<BeautifulCryptoChart>
    with SingleTickerProviderStateMixin {
  
  late String selectedTimeframe;
  List<ChartDataPoint> chartData = [];
  ChartAnalysis? analysis;
  bool isLoading = true;
  String? error;
  int? selectedPointIndex;
  ChartDataPoint? selectedPoint;
  
  late AnimationController _animationController;
  late Animation<double> _chartAnimation;
  late Animation<double> _fadeAnimation;
  
  final ChartDataService _chartService = ChartDataService.instance;

  @override
  void initState() {
    super.initState();
    selectedTimeframe = widget.initialTimeframe;
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2500), // Slightly longer for smoother effect
      vsync: this,
    );
    
    _chartAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.85, curve: Curves.easeOutQuart), // Smoother curve
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.15, 1.0, curve: Curves.easeOutCubic), // Earlier start, smoother fade
    );
    
    _loadChartData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// 📊 Load chart data with proper error handling
  Future<void> _loadChartData() async {
    if (!mounted) return;
    
    setState(() {
      isLoading = true;
      error = null;
      selectedPointIndex = null;
      selectedPoint = null;
    });

    try {
      print('📊 BeautifulChart: Loading data for ${widget.symbol} ($selectedTimeframe)');
      
      final data = await _chartService.getChartData(
        symbol: widget.symbol,
        timeframe: selectedTimeframe,
        currency: 'USD',
      );
      
      if (!mounted) return;

      if (data.isNotEmpty) {
        setState(() {
          chartData = data;
          analysis = ChartAnalysis.fromDataPoints(data);
          isLoading = false;
        });
        
        _animationController.reset();
        _animationController.forward();
        
        print('✅ BeautifulChart: Loaded ${data.length} data points for ${widget.symbol}');
      } else {
        setState(() {
          error = 'No data available for ${widget.symbol}';
          isLoading = false;
        });
      }
      
    } catch (e) {
      print('❌ BeautifulChart: Error loading data: $e');
      if (mounted) {
        setState(() {
          error = 'Failed to load chart data';
          isLoading = false;
        });
      }
    }
  }

  /// 🎨 Build timeframe selector
  Widget _buildTimeframeSelector() {
    if (!widget.showTimeframeSelector) return const SizedBox.shrink();
    
    return Container(
      height: 45,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: ChartTimeframe.predefined.map((timeframe) {
          final isSelected = timeframe.key == selectedTimeframe;
          
          return GestureDetector(
            onTap: () => _selectTimeframe(timeframe.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300), // Smoother transition
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? widget.primaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(25), // More rounded
                border: Border.all(
                  color: isSelected 
                      ? widget.primaryColor 
                      : Colors.grey.withValues(alpha: 0.25),
                  width: isSelected ? 2.0 : 1.0, // Thicker border when selected
                ),
                boxShadow: isSelected ? [
                  BoxShadow(
                    color: widget.primaryColor.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                    spreadRadius: 1,
                  ),
                ] : [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                timeframe.label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 📊 Select timeframe with haptic feedback
  void _selectTimeframe(String timeframe) {
    if (timeframe != selectedTimeframe && !isLoading) {
      HapticFeedback.selectionClick();
      setState(() {
        selectedTimeframe = timeframe;
      });
      _loadChartData();
    }
  }

  /// 📈 Build the main chart
  Widget _buildChart() {
    if (chartData.length < 2) {
          return SizedBox(
      height: widget.height - 100,
      child: const Center(
        child: Text(
          'Insufficient data points for chart',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      ),
    );
    }

    return Container(
      height: widget.height - 100,
      width: double.infinity,
      margin: const EdgeInsets.all(0), // No margin for 100% width
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return GestureDetector(
            onPanUpdate: (details) => _handleChartTouch(details.localPosition),
            onTapDown: (details) => _handleChartTouch(details.localPosition),
            onPanEnd: (_) => _clearSelection(),
            child: CustomPaint(
              size: Size.infinite,
              painter: BeautifulChartPainter(
                dataPoints: chartData,
                primaryColor: widget.primaryColor,
                backgroundColor: widget.backgroundColor,
                animation: _chartAnimation.value,
                selectedIndex: selectedPointIndex,
                analysis: analysis,
                isPriceDown: selectedPoint != null && 
                           selectedPoint!.price < (analysis?.currentPrice ?? chartData.last.price),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 📱 Handle chart touch interactions
  void _handleChartTouch(Offset localPosition) {
    if (chartData.isEmpty) return;
    
    final chartWidth = MediaQuery.of(context).size.width - 32;
    final pointSpacing = chartWidth / (chartData.length - 1);
    final touchedIndex = (localPosition.dx / pointSpacing).round();
    
    if (touchedIndex >= 0 && touchedIndex < chartData.length) {
      if (selectedPointIndex != touchedIndex) {
        HapticFeedback.selectionClick();
        
        final selectedDataPoint = chartData[touchedIndex];
        final currentPrice = analysis?.currentPrice ?? chartData.last.price;
        final isPriceDown = selectedDataPoint.price < currentPrice;
        
        setState(() {
          selectedPointIndex = touchedIndex;
          selectedPoint = selectedDataPoint;
        });
        
        // Notify parent about the selection
        widget.onPointSelected?.call(selectedDataPoint, isPriceDown);
      }
    }
  }

  /// 🔄 Clear selection
  void _clearSelection() {
    if (selectedPointIndex != null) {
      setState(() {
        selectedPointIndex = null;
        selectedPoint = null;
      });
      
      // Notify parent about deselection
      widget.onPointDeselected?.call();
    }
  }





  /// 🔄 Build loading state
  Widget _buildLoadingState() {
    return SizedBox(
      height: widget.height,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(widget.primaryColor),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading chart data...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ❌ Build error state
  Widget _buildErrorState() {
    return SizedBox(
      height: widget.height,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              error ?? 'Chart data unavailable',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadChartData,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        // Remove border radius and shadows for full width design
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeframe selector
          _buildTimeframeSelector(),
          
          // Content
          if (isLoading)
            _buildLoadingState()
          else if (error != null)
            _buildErrorState()
          else ...[
            // Chart
            _buildChart(),
            
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

/// 🎨 Simple Chart Painter - Lightweight and Fast
class BeautifulChartPainter extends CustomPainter {
  final List<ChartDataPoint> dataPoints;
  final Color primaryColor;
  final Color backgroundColor;
  final double animation;
  final int? selectedIndex;
  final ChartAnalysis? analysis;
  final bool isPriceDown;

  BeautifulChartPainter({
    required this.dataPoints,
    required this.primaryColor,
    required this.backgroundColor,
    required this.animation,
    this.selectedIndex,
    this.analysis,
    this.isPriceDown = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.length < 2) return;

    final prices = dataPoints.map((p) => p.price).toList();
    final minPrice = prices.reduce(math.min);
    final maxPrice = prices.reduce(math.max);
    final priceRange = maxPrice - minPrice;
    
    if (priceRange <= 0) return;

    // Choose color based on price direction
    final chartColor = isPriceDown ? Colors.red : primaryColor;

    // Calculate chart points
    final chartPoints = <Offset>[];
    for (int i = 0; i < dataPoints.length; i++) {
      final x = (i / (dataPoints.length - 1)) * size.width;
      final y = size.height - ((dataPoints[i].price - minPrice) / priceRange) * size.height;
      chartPoints.add(Offset(x, y));
    }

    // Animate the number of visible points
    final animatedPointCount = (chartPoints.length * animation).round().clamp(2, chartPoints.length);
    final visiblePoints = chartPoints.take(animatedPointCount).toList();

    // Only draw the main line - no gradient area
    _drawMainLine(canvas, visiblePoints, chartColor);
    _drawDataPoints(canvas, visiblePoints, chartColor);
    _drawSelectedPoint(canvas, visiblePoints, chartColor);
  }

  /// 🎨 Draw simple gradient area under the chart
  void _drawGradientArea(Canvas canvas, Size size, List<Offset> points, Color chartColor) {
    if (points.length < 2) return;

    final gradientPath = Path();
    gradientPath.moveTo(points.first.dx, size.height);
    gradientPath.lineTo(points.first.dx, points.first.dy);
    
    // Draw simple lines to create area
    for (int i = 1; i < points.length; i++) {
      gradientPath.lineTo(points[i].dx, points[i].dy);
    }
    
    gradientPath.lineTo(points.last.dx, size.height);
    gradientPath.close();

    // Simple gradient - lightweight
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          chartColor.withValues(alpha: 0.2 * animation),
          chartColor.withValues(alpha: 0.05 * animation),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(gradientPath, gradientPaint);
  }

  /// 📈 Draw simple and lightweight line chart
  void _drawMainLine(Canvas canvas, List<Offset> points, Color chartColor) {
    if (points.length < 2) return;

    // Simple line paint - lightweight and clean
    final linePaint = Paint()
      ..color = chartColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw simple straight lines between points
    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(path, linePaint);
  }


  /// 🔵 Draw minimal data points - very lightweight
  void _drawDataPoints(Canvas canvas, List<Offset> points, Color chartColor) {
    // For simple line chart, we don't draw data points unless selected
    // This keeps the chart clean and lightweight
    if (selectedIndex != null && selectedIndex! < points.length) {
      // Only draw a small point at the selected location
      final pointPaint = Paint()
        ..color = chartColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(points[selectedIndex!], 3, pointPaint);
    }
  }

  /// 🎯 Draw simple selected point - lightweight
  void _drawSelectedPoint(Canvas canvas, List<Offset> points, Color chartColor) {
    if (selectedIndex == null || selectedIndex! >= points.length) return;

    final selectedPoint = points[selectedIndex!];
    
    // Draw simple vertical line
    final linePaint = Paint()
      ..color = chartColor.withValues(alpha: 0.6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    canvas.drawLine(
      Offset(selectedPoint.dx, 0),
      Offset(selectedPoint.dx, points.last.dy + 50),
      linePaint,
    );

    // Draw simple selected point
    final selectedPointBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final selectedPointPaint = Paint()
      ..color = chartColor
      ..style = PaintingStyle.fill;

    // Simple circles
    canvas.drawCircle(selectedPoint, 6, selectedPointBorderPaint);
    canvas.drawCircle(selectedPoint, 4, selectedPointPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
