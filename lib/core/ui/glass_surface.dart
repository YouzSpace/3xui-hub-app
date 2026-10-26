import 'dart:ui';

import 'package:flutter/material.dart';

import 'device_tier.dart';

/// 液体玻璃材质（T1.12，ui-glass-motion.md §2.3）。
///
/// 三层结构缺一不可：高光层 + 色调层 + 模糊层。
/// 只用在白名单（底部导航、滚动后 AppBar、对话框、底部面板、连接按钮外环）。
/// 低端机自动降级为纯色、不调用 BackdropFilter。
class GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final double blur;

  const GlassSurface({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(16)),
    this.blur = 24,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    // ② 色调层：亮 0.55 / 暗 0.62（两套参数不同，不许照搬）。
    final base = dark ? cs.surfaceContainer : cs.surfaceContainerLowest;
    final tint = base.withValues(alpha: dark ? 0.62 : 0.55);

    final body = Stack(
      children: [
        // 底色 + 边框 + 阴影（BoxDecoration 的 color 和 gradient 互斥，高光单独叠）。
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tint,
              borderRadius: radius,
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.08 : 0.70),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.30 : 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),
        ),
        // ① 高光层：顶部 40% 高度渐变白，制造「上缘被打亮」的厚度。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 48,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(top: radius.topLeft),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.06 : 0.50),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );

    final clipped = ClipRRect(borderRadius: radius, child: body);

    // ③ 模糊层：低端机降级为纯色，避免掉帧。
    if (isLowEndDevice) return RepaintBoundary(child: clipped);
    return RepaintBoundary(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: clipped,
      ),
    );
  }
}
