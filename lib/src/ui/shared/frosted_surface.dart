import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class FrostedSurface extends StatelessWidget {
  const FrostedSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: appMainSurfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: appDialogBorderColor),
          ),
          child: child,
        ),
      ),
    );
  }
}
