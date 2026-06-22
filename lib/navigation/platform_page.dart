import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

CustomTransitionPage<T> platformPage<T>({
  required Widget child,
  required GoRouterState state,
  bool fullscreenDialog = false,
}) {
  if (Platform.isIOS) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      name: state.matchedLocation,
      fullscreenDialog: fullscreenDialog,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final offset = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return SlideTransition(position: offset, child: child);
      },
    );
  }
  return CustomTransitionPage<T>(
    key: state.pageKey,
    name: state.matchedLocation,
    fullscreenDialog: fullscreenDialog,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return const FadeUpwardsPageTransitionsBuilder().buildTransitions(
        null,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    },
  );
}
