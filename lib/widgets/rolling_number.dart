import 'package:flutter/material.dart';

import '../core/ui/motion.dart';

/// 数字滚动过渡（§3.2 #10 / T5.3）：旧值滑出、新值滑入，400ms，不直接换字。
///
/// 换字时新值自下而上、旧值向上滑出；等宽数字（tabular figures）保证宽度不抖。
class RollingNumber extends StatelessWidget {
  const RollingNumber({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    final key = ValueKey<String>(text);
    return AnimatedSwitcher(
      duration: Motion.panel,
      switchInCurve: Motion.easeOut,
      switchOutCurve: Motion.easeIn,
      transitionBuilder: (child, animation) {
        final incoming = child.key == key;
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, incoming ? 0.6 : -0.6),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: Text(
        text,
        key: key,
        style: base?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
