import 'package:flutter/material.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.title,
    this.actions,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.extendBody = false,
    this.leading,
    this.centerTitle,
    this.showBackButton = true,
  });

  final String? title;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool extendBody;
  final Widget? leading;
  final bool? centerTitle;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBody: extendBody,
      appBar: title != null
          ? AppBar(
              title: Text(title!),
              centerTitle: centerTitle,
              leading: leading ??
                  (showBackButton && canPop
                      ? BackButton(color: scheme.onSurface)
                      : null),
              actions: actions,
            )
          : null,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
