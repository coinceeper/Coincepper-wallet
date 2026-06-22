import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/network_provider.dart';
import '../screens/network_error_dialog.dart';
import '../services/network_monitor.dart';
import 'package:flutter/services.dart';

class NetworkOverlay extends StatefulWidget {
  final Widget child;
  const NetworkOverlay({required this.child, super.key});

  @override
  State<NetworkOverlay> createState() => _NetworkOverlayState();
}

class _NetworkOverlayState extends State<NetworkOverlay> {
  bool _showDialog = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Consumer2<NetworkProvider, NetworkMonitor>(
          builder: (context, networkProvider, networkMonitor, _) {
            final isOnlineFromProvider = networkProvider.isOnline;
            final isOnlineFromMonitor = networkMonitor.isOnline;
            final isOnline = isOnlineFromProvider && isOnlineFromMonitor;

            // فقط رنگ نوار بالای صفحه را قرمز کن
            if (!isOnline) {
              // تغییر رنگ status bar
              SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
                statusBarColor: Colors.red,
                statusBarIconBrightness: Brightness.light,
              ));
            } else {
              // بازگرداندن رنگ status bar به حالت پیش‌فرض
              SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
              ));
            }

            Widget errorDialog = _showDialog 
                ? NetworkErrorDialog(
                    onDismiss: () {
                      if (isOnline) {
                        setState(() {
                          _showDialog = false;
                        });
                      }
                    },
                  )
                : const SizedBox.shrink();

            if (!isOnline && !_showDialog) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  _showDialog = true;
                });
              });
            } else if (isOnline && _showDialog) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  _showDialog = false;
                });
              });
            }

            return Stack(
              children: [
                if (_showDialog) errorDialog,
              ],
            );
          },
        ),
      ],
    );
  }
} 