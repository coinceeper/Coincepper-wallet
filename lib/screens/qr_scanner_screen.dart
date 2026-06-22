import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/qr_navigation_manager.dart';

class QrScannerScreen extends StatefulWidget {
  final String returnScreen;
  
  const QrScannerScreen({
    super.key,
    this.returnScreen = 'home',
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool scanned = false;
  MobileScannerController controller = MobileScannerController();

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onQRCodeDetected(String code) async {
    if (scanned) return;
    scanned = true;
    
    try {
      // Process QR scan result using QRNavigationManager
      await QRNavigationManager.handleQRScannerResult(
        context,
        code,
        widget.returnScreen,
      );
      
      // Close the scanner screen
      Navigator.of(context).pop();
    } catch (e) {
      print('❌ Error handling QR scan result: $e');
      // Fallback: return the code as before
      Navigator.of(context).pop(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_safeTranslate('scan_qr_code', 'Scan QR Code'), style: const TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _onQRCodeDetected(barcode.rawValue!);
                  break;
                }
              }
            },
            fit: BoxFit.contain,
          ),
          // Custom overlay
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
            ),
            child: Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.blue,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  elevation: 0,
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_safeTranslate('cancel', 'Cancel')),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 