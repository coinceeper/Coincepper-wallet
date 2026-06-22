import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class ErrorBottomSheet extends StatelessWidget {
  final String message;
  final String? title;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const ErrorBottomSheet({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.iconColor,
    this.onRetry,
    this.onDismiss,
  });

  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  /// نمایش error modal از پایین صفحه
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    IconData? icon,
    Color? iconColor,
    VoidCallback? onRetry,
    VoidCallback? onDismiss,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ErrorBottomSheet(
        message: message,
        title: title,
        icon: icon,
        iconColor: iconColor,
        onRetry: onRetry,
        onDismiss: onDismiss,
      ),
    );
  }

  /// تشخیص نوع خطا و انتخاب آیکون و رنگ مناسب
  _ErrorType _getErrorType() {
    final lowerMessage = message.toLowerCase();
    
    if (lowerMessage.contains('internet') || 
        lowerMessage.contains('connection') || 
        lowerMessage.contains('network')) {
      return _ErrorType.network;
    } else if (lowerMessage.contains('server') || 
               lowerMessage.contains('cloudflare') || 
               lowerMessage.contains('security')) {
      return _ErrorType.server;
    } else if (lowerMessage.contains('timeout')) {
      return _ErrorType.timeout;
    } else if (lowerMessage.contains('already been imported') || 
               lowerMessage.contains('duplicate') || 
               lowerMessage.contains('exists')) {
      return _ErrorType.duplicate;
    } else if (lowerMessage.contains('invalid') || 
               lowerMessage.contains('incorrect') || 
               lowerMessage.contains('wrong')) {
      return _ErrorType.validation;
    } else {
      return _ErrorType.general;
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorType = _getErrorType();
    final errorConfig = _getErrorConfig(context, errorType);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              
              // Error icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: (iconColor ?? errorConfig.color).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon ?? errorConfig.icon,
                  size: 32,
                  color: iconColor ?? errorConfig.color,
                ),
              ),
              const SizedBox(height: 20),
              
              // Title
              Text(
                title ?? errorConfig.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              
              // Message
              Text(
                message,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              // Buttons
              Row(
                children: [
                  // Dismiss button
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onDismiss?.call();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.grey[100],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _safeTranslate(context, 'ok', 'OK'),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  
                  // Retry button (if available)
                  if (onRetry != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onRetry!();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: errorConfig.color,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _safeTranslate(context, 'try_again', 'Try Again'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  _ErrorConfig _getErrorConfig(BuildContext context, _ErrorType type) {
    switch (type) {
      case _ErrorType.network:
        return _ErrorConfig(
          title: _safeTranslate(context, 'connection_error', 'Connection Error'),
          icon: Icons.wifi_off,
          color: Colors.orange,
        );
      case _ErrorType.server:
        return _ErrorConfig(
          title: _safeTranslate(context, 'server_error', 'Server Error'),
          icon: Icons.cloud_off,
          color: Colors.red,
        );
      case _ErrorType.timeout:
        return _ErrorConfig(
          title: _safeTranslate(context, 'timeout_error', 'Timeout Error'),
          icon: Icons.access_time,
          color: Colors.amber,
        );
      case _ErrorType.duplicate:
        return _ErrorConfig(
          title: _safeTranslate(context, 'duplicate_error', 'Already Exists'),
          icon: Icons.warning,
          color: Colors.orange,
        );
      case _ErrorType.validation:
        return _ErrorConfig(
          title: _safeTranslate(context, 'validation_error', 'Invalid Input'),
          icon: Icons.error_outline,
          color: Colors.red,
        );
      case _ErrorType.general:
      default:
        return _ErrorConfig(
          title: _safeTranslate(context, 'error', 'Error'),
          icon: Icons.error,
          color: Colors.red,
        );
    }
  }
}

enum _ErrorType {
  network,
  server,
  timeout,
  duplicate,
  validation,
  general,
}

class _ErrorConfig {
  final String title;
  final IconData icon;
  final Color color;

  _ErrorConfig({
    required this.title,
    required this.icon,
    required this.color,
  });
}
