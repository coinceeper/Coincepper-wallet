import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/version_check_service.dart';
import '../services/build_secrets.dart';
import '../utils/secure_log.dart';

class _AppBrand {
  static const Color teal = Color(0xFF0BAB9B);
  static const Color tealLight = Color(0xFF4DD0C6);
  static const Color tealBg = Color(0xFFE0F7F5);
  static const Color tealGradientStart = Color(0xFF0BAB9B);
  static const Color tealGradientEnd = Color(0xFF06D6B8);
}

/// Returns the platform-specific store URL for the current device.
/// Android → Google Play, iOS → Apple App Store.
/// Fallback uses [BuildSecrets.coinceeperWebUrl] so the domain is centralized.
String _defaultStoreUrl() {
  if (Platform.isAndroid) {
    return 'https://play.google.com/store/apps/details?id=com.coinceeper.adl';
  }
  if (Platform.isIOS) {
    return 'https://apps.apple.com/tr/app/coinceeper/id6749888477?l=tr';
  }
  return BuildSecrets.coinceeperWebUrl;
}

class ForceUpdateScreen extends StatefulWidget {
  final VersionStatus status;
  final VoidCallback? onLater;

  const ForceUpdateScreen({super.key, required this.status, this.onLater});

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _currentVersion = info.version);
      }
    } catch (e) {
      SecureLog.w('ForceUpdateScreen: failed to load current app version', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isForce = widget.status.type == UpdateType.force;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !isForce,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      const Color(0xFF0D2B28),
                      const Color(0xFF081A18),
                      const Color(0xFF000000),
                    ]
                  : [
                      const Color(0xFFE8F9F7),
                      const Color(0xFFF5FCFB),
                      Colors.white,
                    ],
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
          child: Stack(
            children: [
              if (!isDark) ..._buildLightBlobs(),
              if (isDark) ..._buildDarkBlobs(),

              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 16),

                        _AnimatedPulse(
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  _AppBrand.tealGradientStart,
                                  _AppBrand.tealGradientEnd,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(32),
                              boxShadow: [
                                BoxShadow(
                                  color: _AppBrand.teal.withValues(alpha: 0.3),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.system_update_rounded,
                                size: 56,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),

                        Text(
                          isForce
                              ? tr('update.force_title')
                              : tr('update.optional_title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF1A2E2A),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 14),

                        Text(
                          isForce
                              ? tr('update.force_message',
                                  args: [widget.status.latestVersion ?? ''])
                              : tr('update.optional_message',
                                  args: [widget.status.latestVersion ?? '']),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.7)
                                : const Color(0xFF5A6B67),
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 28),

                        if (widget.status.latestVersion != null)
                          _VersionCard(
                            currentVersion: _currentVersion,
                            latestVersion: widget.status.latestVersion!,
                            isDark: isDark,
                          ),
                        const SizedBox(height: 36),

                        _PremiumButton(
                          label: tr('update.update_now'),
                          onTap: () => _launchURL(),
                          isDark: isDark,
                        ),

                        if (!isForce) ...[
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: () {
                              widget.onLater?.call();
                              Navigator.pop(context);
                            },
                            style: TextButton.styleFrom(
                              minimumSize: const Size(double.infinity, 54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              foregroundColor: isDark
                                  ? Colors.white.withValues(alpha: 0.6)
                                  : const Color(0xFF6B7B77),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              tr('update.later'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLightBlobs() {
    return [
      Positioned(
        top: -60, right: -40,
        child: Container(
          width: 200, height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _AppBrand.tealBg.withValues(alpha: 0.5),
          ),
        ),
      ),
      Positioned(
        top: 80, left: -50,
        child: Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _AppBrand.tealLight.withValues(alpha: 0.15),
          ),
        ),
      ),
      Positioned(
        bottom: 100, right: -30,
        child: Container(
          width: 160, height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _AppBrand.tealLight.withValues(alpha: 0.12),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildDarkBlobs() {
    return [
      Positioned(
        top: -60, right: -40,
        child: Container(
          width: 200, height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _AppBrand.teal.withValues(alpha: 0.08),
          ),
        ),
      ),
      Positioned(
        bottom: 80, left: -40,
        child: Container(
          width: 150, height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _AppBrand.tealLight.withValues(alpha: 0.05),
          ),
        ),
      ),
    ];
  }

  Future<void> _launchURL() async {
    final uri = Uri.parse(_defaultStoreUrl());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ─── Pulse animation ──────────────────────────────────────────────────────
class _AnimatedPulse extends StatefulWidget {
  final Widget child;
  const _AnimatedPulse({required this.child});

  @override
  State<_AnimatedPulse> createState() => _AnimatedPulseState();
}

class _AnimatedPulseState extends State<_AnimatedPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ─── Version comparison card ──────────────────────────────────────────────
class _VersionCard extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;
  final bool isDark;

  const _VersionCard({
    required this.currentVersion,
    required this.latestVersion,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : _AppBrand.teal.withValues(alpha: 0.15),
          width: 1.2,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: _AppBrand.teal.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        children: [
          Text(
            tr('update.new_version'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.5)
                  : const Color(0xFF8A9C97),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _VersionPill(
                label: tr('update.current'),
                version: currentVersion,
                isDark: isDark,
                isCurrent: true,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: _AppBrand.teal,
                ),
              ),
              _VersionPill(
                label: tr('update.new'),
                version: latestVersion,
                isDark: isDark,
                isCurrent: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VersionPill extends StatelessWidget {
  final String label;
  final String version;
  final bool isDark;
  final bool isCurrent;

  const _VersionPill({
    required this.label,
    required this.version,
    required this.isDark,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrent
            ? (isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade100)
            : _AppBrand.teal.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isCurrent
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.5)
                      : Colors.grey.shade500)
                  : _AppBrand.teal,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            version,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isCurrent
                  ? (isDark ? Colors.white : const Color(0xFF2D3E3A))
                  : _AppBrand.teal,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Premium gradient button ──────────────────────────────────────────────
class _PremiumButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _PremiumButton({
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<_PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<_PremiumButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              _AppBrand.tealGradientStart,
              _AppBrand.tealGradientEnd,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _AppBrand.teal.withValues(alpha: _pressed ? 0.2 : 0.35),
              blurRadius: _pressed ? 12 : 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Transform.scale(
            scale: _pressed ? 0.97 : 1.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
