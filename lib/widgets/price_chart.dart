import 'package:flutter/material.dart';
import 'dart:math';
import '../services/coinmarketcap_service 2.dart';

/// SVG-based price chart widget for cryptocurrency price visualization
class PriceChart extends StatelessWidget {
  final List<ChartDataPoint> data;
  final double width;
  final double height;
  final Color lineColor;
  final Color gradientStartColor;
  final Color gradientEndColor;
  final double strokeWidth;
  
  const PriceChart({
    super.key,
    required this.data,
    this.width = 350,
    this.height = 200,
    this.lineColor = const Color(0xFF2196F3),
    this.gradientStartColor = const Color(0x402196F3),
    this.gradientEndColor = const Color(0x002196F3),
    this.strokeWidth = 2.0,
  });
  
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'No chart data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    
    return CustomPaint(
      size: Size(width, height),
      painter: ChartPainter(
        data: data,
        lineColor: lineColor,
        gradientStartColor: gradientStartColor,
        gradientEndColor: gradientEndColor,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

/// Custom painter for drawing the price chart
class ChartPainter extends CustomPainter {
  final List<ChartDataPoint> data;
  final Color lineColor;
  final Color gradientStartColor;
  final Color gradientEndColor;
  final double strokeWidth;
  
  ChartPainter({
    required this.data,
    required this.lineColor,
    required this.gradientStartColor,
    required this.gradientEndColor,
    required this.strokeWidth,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    // Find min and max prices for scaling
    double minPrice = data.map((d) => d.price).reduce(min);
    double maxPrice = data.map((d) => d.price).reduce(max);
    
    // Add some padding to the price range
    double priceRange = maxPrice - minPrice;
    if (priceRange == 0) priceRange = maxPrice * 0.1; // Avoid division by zero
    minPrice -= priceRange * 0.1;
    maxPrice += priceRange * 0.1;
    
    // Create path for the line
    Path linePath = Path();
    Path gradientPath = Path();
    
    for (int i = 0; i < data.length; i++) {
      double x = (i / (data.length - 1)) * size.width;
      double y = size.height - ((data[i].price - minPrice) / (maxPrice - minPrice)) * size.height;
      
      if (i == 0) {
        linePath.moveTo(x, y);
        gradientPath.moveTo(x, size.height);
        gradientPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        gradientPath.lineTo(x, y);
      }
    }
    
    // Complete the gradient path
    gradientPath.lineTo(size.width, size.height);
    gradientPath.close();
    
    // Draw gradient fill
    Paint gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [gradientStartColor, gradientEndColor],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    
    canvas.drawPath(gradientPath, gradientPaint);
    
    // Draw the line
    Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    
    canvas.drawPath(linePath, linePaint);
    
    // Draw data points (optional, for better visibility)
    Paint pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    
    for (int i = 0; i < data.length; i++) {
      if (i % (data.length ~/ 10) == 0 || i == data.length - 1) { // Show only some points
        double x = (i / (data.length - 1)) * size.width;
        double y = size.height - ((data[i].price - minPrice) / (maxPrice - minPrice)) * size.height;
        canvas.drawCircle(Offset(x, y), 3, pointPaint);
      }
    }
  }
  
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

/// Interactive price chart with touch support
class InteractivePriceChart extends StatefulWidget {
  final List<ChartDataPoint> data;
  final double width;
  final double height;
  final Color lineColor;
  final Function(ChartDataPoint?)? onPointSelected;
  
  const InteractivePriceChart({
    super.key,
    required this.data,
    this.width = 350,
    this.height = 200,
    this.lineColor = const Color(0xFF2196F3),
    this.onPointSelected,
  });
  
  @override
  State<InteractivePriceChart> createState() => _InteractivePriceChartState();
}

class _InteractivePriceChartState extends State<InteractivePriceChart> {
  ChartDataPoint? selectedPoint;
  Offset? touchPosition;
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          touchPosition = details.localPosition;
          _updateSelectedPoint();
        });
      },
      onPanEnd: (details) {
        setState(() {
          touchPosition = null;
          selectedPoint = null;
        });
      },
      child: Stack(
        children: [
          CustomPaint(
            size: Size(widget.width, widget.height),
            painter: InteractiveChartPainter(
              data: widget.data,
              lineColor: widget.lineColor,
              selectedPoint: selectedPoint,
              touchPosition: touchPosition,
            ),
          ),
          if (selectedPoint != null && touchPosition != null)
            Positioned(
              left: touchPosition!.dx - 50,
              top: touchPosition!.dy - 40,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '\$${selectedPoint!.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  void _updateSelectedPoint() {
    if (touchPosition == null || widget.data.isEmpty) return;
    
    double normalizedX = touchPosition!.dx / widget.width;
    int index = (normalizedX * (widget.data.length - 1)).round();
    index = index.clamp(0, widget.data.length - 1);
    
    selectedPoint = widget.data[index];
    widget.onPointSelected?.call(selectedPoint);
  }
}

/// Interactive chart painter with touch support
class InteractiveChartPainter extends CustomPainter {
  final List<ChartDataPoint> data;
  final Color lineColor;
  final ChartDataPoint? selectedPoint;
  final Offset? touchPosition;
  
  InteractiveChartPainter({
    required this.data,
    required this.lineColor,
    this.selectedPoint,
    this.touchPosition,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    // Find min and max prices for scaling
    double minPrice = data.map((d) => d.price).reduce(min);
    double maxPrice = data.map((d) => d.price).reduce(max);
    
    // Add some padding to the price range
    double priceRange = maxPrice - minPrice;
    if (priceRange == 0) priceRange = maxPrice * 0.1;
    minPrice -= priceRange * 0.1;
    maxPrice += priceRange * 0.1;
    
    // Create path for the line
    Path linePath = Path();
    Path gradientPath = Path();
    
    for (int i = 0; i < data.length; i++) {
      double x = (i / (data.length - 1)) * size.width;
      double y = size.height - ((data[i].price - minPrice) / (maxPrice - minPrice)) * size.height;
      
      if (i == 0) {
        linePath.moveTo(x, y);
        gradientPath.moveTo(x, size.height);
        gradientPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        gradientPath.lineTo(x, y);
      }
    }
    
    // Complete the gradient path
    gradientPath.lineTo(size.width, size.height);
    gradientPath.close();
    
    // Draw gradient fill
    Paint gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lineColor.withOpacity(0.3), lineColor.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    
    canvas.drawPath(gradientPath, gradientPaint);
    
    // Draw the line
    Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    
    canvas.drawPath(linePath, linePaint);
    
    // Draw touch indicator
    if (touchPosition != null && selectedPoint != null) {
      Paint indicatorPaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.fill;
      
      // Draw vertical line
      canvas.drawLine(
        Offset(touchPosition!.dx, 0),
        Offset(touchPosition!.dx, size.height),
        Paint()
          ..color = lineColor.withOpacity(0.5)
          ..strokeWidth = 1,
      );
      
      // Draw point
      canvas.drawCircle(touchPosition!, 4, indicatorPaint);
      canvas.drawCircle(
        touchPosition!,
        4,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }
  
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
