import 'package:flutter/material.dart';

import '../core/theme/spacing.dart';

/// 通用卡片（T1.7，design-tokens §6.2）：不透明 MD3 色阶，圆角 12，无阴影。
///
/// 玻璃禁止用在卡片上（ui-glass-motion §2.1 白名单）。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Sp.base),
    this.margin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: margin,
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      // 卡片圆角 12（theme 已设），水波纹跟随圆角。
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: card,
    );
  }
}
