import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ui/motion.dart';
import 'connect_button.dart';

/// 连接按钮的两圈光效（§3.3）：连接中的扩散脉冲、已连接的呼吸光晕。
///
/// 都在按钮本体之外、[IgnorePointer] 包裹，不参与命中测试。

/// 已连接：呼吸光晕（opacity 0.25↔0.08、scale 1.0↔1.06）+ 玻璃外环。
class ConnectHaloRing extends StatelessWidget {
  const ConnectHaloRing({
    super.key,
    required this.progress,
    required this.diameter,
    required this.reduced,
  });

  /// 0..1（往返循环）。
  final Animation<double> progress;
  final double diameter;

  /// 系统「移除动画」：锁在中间值，只留一圈静态淡光。
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          final t = reduced ? 0.5 : progress.value;
          final opacity = 0.08 + 0.17 * t;
          return Transform.scale(
            scale: 1 + 0.06 * t,
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: opacity),
                border: Border.all(
                  color: cs.primary.withValues(alpha: opacity * 1.6),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 连接中：半透明环 1.0 → 1.35 扩散淡出（easeOut，禁 linear）。
class ConnectPulseRing extends StatelessWidget {
  const ConnectPulseRing({
    super.key,
    required this.progress,
    required this.diameter,
    required this.reduced,
  });

  final Animation<double> progress;
  final double diameter;
  final bool reduced;

  /// 扩散上限（§3.3：1.0 → 1.35）。
  static const double maxScale = 1.35;

  @override
  Widget build(BuildContext context) {
    if (reduced) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          final t = Motion.easeOut.transform(progress.value);
          return Transform.scale(
            scale: 1 + (maxScale - 1) * t,
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  width: 2,
                  color: cs.primary.withValues(alpha: 0.45 * (1 - t)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 连接中「…」逐个出现（§3.3），也可给首页状态文字复用。
class ConnectingDots extends StatefulWidget {
  const ConnectingDots({super.key, this.style});

  final TextStyle? style;

  @override
  State<ConnectingDots> createState() => _ConnectingDotsState();
}

class _ConnectingDotsState extends State<ConnectingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ConnectButton.pulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? Theme.of(context).textTheme.bodySmall;
    if (MediaQuery.of(context).disableAnimations) {
      return Text('…', style: style);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final count = math.min(3, (_controller.value * 3).floor() + 1);
        return Text('.' * count, style: style);
      },
    );
  }
}
