import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/enhanced_network_manager.dart';

/// Widget to display current network status and quality
class NetworkStatusWidget extends StatefulWidget {
  final bool showDetails;
  final VoidCallback? onTap;
  
  const NetworkStatusWidget({
    super.key,
    this.showDetails = false,
    this.onTap,
  });

  @override
  State<NetworkStatusWidget> createState() => _NetworkStatusWidgetState();
}

class _NetworkStatusWidgetState extends State<NetworkStatusWidget> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _networkStatus;

  @override
  void initState() {
    super.initState();
    _updateNetworkStatus();
    
    // Update status every 30 seconds
    Stream.periodic(const Duration(seconds: 30)).listen((_) {
      if (mounted) {
        _updateNetworkStatus();
      }
    });
  }

  void _updateNetworkStatus() {
    setState(() {
      _networkStatus = _apiService.getNetworkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_networkStatus == null) {
      return const SizedBox.shrink();
    }

    final quality = _networkStatus!['quality'] as String;
    final isVpn = _networkStatus!['isVpnActive'] as bool;
    final responseTime = _networkStatus!['lastResponseTime'] as int;
    final successRate = _networkStatus!['successRate'] as String;

    return GestureDetector(
      onTap: widget.onTap ?? () => _showNetworkDetails(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _getQualityColor(quality).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getQualityColor(quality).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getQualityIcon(quality, isVpn),
              size: 16,
              color: _getQualityColor(quality),
            ),
            const SizedBox(width: 4),
            if (widget.showDetails) ...[
              Text(
                _getQualityText(quality, isVpn),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _getQualityColor(quality),
                ),
              ),
              if (responseTime > 0) ...[
                Text(
                  ' (${responseTime}ms)',
                  style: TextStyle(
                    fontSize: 10,
                    color: _getQualityColor(quality).withOpacity(0.7),
                  ),
                ),
              ],
            ] else ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _getQualityColor(quality),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getQualityColor(String quality) {
    switch (quality) {
      case 'excellent':
        return Colors.green;
      case 'good':
        return Colors.lightGreen;
      case 'fair':
        return Colors.orange;
      case 'poor':
        return Colors.red;
      case 'vpn':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getQualityIcon(String quality, bool isVpn) {
    if (isVpn) return Icons.vpn_lock;
    
    switch (quality) {
      case 'excellent':
        return Icons.wifi;
      case 'good':
        return Icons.wifi;
      case 'fair':
        return Icons.wifi_2_bar;
      case 'poor':
        return Icons.wifi_1_bar;
      default:
        return Icons.wifi_off;
    }
  }

  String _getQualityText(String quality, bool isVpn) {
    if (isVpn) return 'VPN';
    
    switch (quality) {
      case 'excellent':
        return 'عالی';
      case 'good':
        return 'خوب';
      case 'fair':
        return 'متوسط';
      case 'poor':
        return 'ضعیف';
      default:
        return 'نامشخص';
    }
  }

  void _showNetworkDetails(BuildContext context) {
    if (_networkStatus == null) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.network_check, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              const Text('وضعیت شبکه'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('کیفیت اتصال', _getQualityText(_networkStatus!['quality'], _networkStatus!['isVpnActive'])),
              _buildDetailRow('زمان پاسخ', '${_networkStatus!['lastResponseTime']}ms'),
              _buildDetailRow('نرخ موفقیت', '${_networkStatus!['successRate']}%'),
              _buildDetailRow('VPN فعال', _networkStatus!['isVpnActive'] ? 'بله' : 'خیر'),
              const SizedBox(height: 16),
              const Text(
                'تنظیمات Timeout (ثانیه):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildDetailRow('اتصال', '${_networkStatus!['timeouts']['connect']}s'),
              _buildDetailRow('دریافت', '${_networkStatus!['timeouts']['receive']}s'),
              _buildDetailRow('ارسال', '${_networkStatus!['timeouts']['send']}s'),
              const SizedBox(height: 16),
              const Text(
                'تنظیمات Retry:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildDetailRow('حداکثر تلاش', '${_networkStatus!['retryConfig']['maxRetries']}'),
              _buildDetailRow('تأخیر پایه', '${_networkStatus!['retryConfig']['baseDelay']}s'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _updateNetworkStatus();
                Navigator.of(context).pop();
              },
              child: const Text('به‌روزرسانی'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('بستن'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

/// Compact network status indicator for showing in app bars
class NetworkStatusIndicator extends StatelessWidget {
  const NetworkStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const NetworkStatusWidget(showDetails: false);
  }
}

/// Detailed network status widget for settings screens
class DetailedNetworkStatus extends StatelessWidget {
  const DetailedNetworkStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return const NetworkStatusWidget(showDetails: true);
  }
}
