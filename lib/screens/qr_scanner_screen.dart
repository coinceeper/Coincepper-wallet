import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:permission_handler/permission_handler.dart';

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
  bool _cameraUnavailable = false;
  String? _statusMessage;
  final TextEditingController _manualController = TextEditingController();
  late final MobileScannerController controller = MobileScannerController(
    autoStart: false,
  );

  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    _prepareCamera();
  }

  Future<void> _prepareCamera() async {
    if (kIsWeb) {
      setState(() {
        _cameraUnavailable = true;
        _statusMessage = _safeTranslate(
          'qr_camera_unavailable',
          'Camera scanning is not available here. Paste a QR payload below.',
        );
      });
      return;
    }

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _cameraUnavailable = true;
        _statusMessage = _safeTranslate(
          'qr_camera_denied',
          'Camera access was denied. Paste a QR payload below or enable Camera in System Settings.',
        );
      });
      return;
    }

    try {
      await controller.start();
      if (mounted) {
        setState(() {
          _cameraUnavailable = false;
          _statusMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraUnavailable = true;
          _statusMessage = _safeTranslate(
            'qr_camera_start_failed',
            'Could not start the camera. Paste a QR payload below.',
          );
        });
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _submitCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || scanned) return;
    scanned = true;

    try {
      await QRNavigationManager.handleQRScannerResult(
        context,
        trimmed,
        widget.returnScreen,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      scanned = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _safeTranslate('qr_scan_failed', 'Could not process this QR code.'),
            ),
          ),
        );
      }
    }
  }

  void _onQRCodeDetected(String code) => _submitCode(code);

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _safeTranslate('clipboard_empty', 'Clipboard is empty.'),
          ),
        ),
      );
      return;
    }
    _manualController.text = text;
    await _submitCode(text);
  }

  Widget _manualEntryPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_statusMessage != null) ...[
            Text(
              _statusMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _manualController,
            style: const TextStyle(color: Colors.white),
            maxLines: 4,
            decoration: InputDecoration(
              hintText: _safeTranslate(
                'paste_qr_payload',
                'Paste wallet address or QR text',
              ),
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _submitCode(_manualController.text),
            child: Text(_safeTranslate('use_pasted_code', 'Use pasted code')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _pasteFromClipboard,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            child: Text(_safeTranslate('paste_from_clipboard', 'Paste from clipboard')),
          ),
          if (!_cameraUnavailable) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                setState(() => _cameraUnavailable = false);
                await _prepareCamera();
              },
              child: Text(_safeTranslate('retry_camera', 'Retry camera')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scannerOverlay() {
    return IgnorePointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showManualOnly = _cameraUnavailable;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _safeTranslate('scan_qr_code', 'Scan QR Code'),
          style: const TextStyle(color: Colors.white),
        ),
        elevation: 0,
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: showManualOnly
                ? Center(
                    child: Icon(
                      Icons.qr_code_scanner,
                      size: 72,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: controller,
                        onDetect: (capture) {
                          for (final barcode in capture.barcodes) {
                            final value = barcode.rawValue;
                            if (value != null && value.isNotEmpty) {
                              _onQRCodeDetected(value);
                              break;
                            }
                          }
                        },
                        fit: BoxFit.cover,
                        errorBuilder: (context, error) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted || _cameraUnavailable) return;
                            setState(() {
                              _cameraUnavailable = true;
                              _statusMessage = _safeTranslate(
                                'qr_camera_error',
                                'Camera error. Paste a QR payload below.',
                              );
                            });
                          });
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                error.errorDetails?.message ??
                                    _safeTranslate(
                                      'unexpected_error',
                                      'An unexpected error occurred',
                                    ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          );
                        },
                      ),
                      _scannerOverlay(),
                    ],
                  ),
          ),
          _manualEntryPanel(),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
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
        ],
      ),
    );
  }
}
