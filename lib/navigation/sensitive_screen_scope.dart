import 'package:flutter/material.dart';

import '../services/screen_protection.dart';

/// Enables screenshot protection while this route is visible.
class SensitiveScreenScope extends StatefulWidget {
  const SensitiveScreenScope({super.key, required this.child});

  final Widget child;

  @override
  State<SensitiveScreenScope> createState() => _SensitiveScreenScopeState();
}

class _SensitiveScreenScopeState extends State<SensitiveScreenScope> {
  @override
  void initState() {
    super.initState();
    ScreenProtection.enable();
  }

  @override
  void dispose() {
    ScreenProtection.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
