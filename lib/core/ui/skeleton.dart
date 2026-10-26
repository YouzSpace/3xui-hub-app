import 'package:flutter/material.dart';

import 'motion.dart';

/// 骨架屏（T1.14，ui-glass-motion.md §3.2 #6）：
/// 扫光周期 1.5s（[Motion.shimmer]）、峰值透明度 0.15、一页只有一道光带。
/// 玻璃禁入滚动列表，骨架全部不透明底色，无 BackdropFilter。

/// 扫光峰值透明度（§3.2 #6）。
const double _shimmerPeakOpacity = 0.15;

/// 扫光方向：一道光带从左上滑到右下。
const AlignmentGeometry _shimmerBegin = Alignment(-1.4, -0.4);
const AlignmentGeometry _shimmerEnd = Alignment(1.4, 0.4);

/// 共用扫光动画：给子树提供 0..1 相位，所有骨架共享同一道光带。
class _ShimmerPhase extends StatefulWidget {
  final Widget Function(BuildContext context, double phase) builder;

  const _ShimmerPhase({required this.builder});

  @override
  State<_ShimmerPhase> createState() => _ShimmerPhaseState();
}

class _ShimmerPhaseState extends State<_ShimmerPhase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.shimmer,
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 系统「移除动画」时停住扫光，只保留底色（§3.5）。
    if (MediaQuery.of(context).disableAnimations) {
      return widget.builder(context, 0);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(context, _controller.value),
    );
  }
}

/// 扫光随相位平移（相位 0..1 映射到 -1..1）。
class _SlidingGradientTransform extends GradientTransform {
  final double phase;
  const _SlidingGradientTransform(this.phase);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (phase * 2 - 1), 0, 0);
  }
}

/// 单块骨架：圆角矩形底色 + 一道扫光。
class SkeletonCard extends StatelessWidget {
  final double height;
  final BorderRadius radius;

  const SkeletonCard({
    super.key,
    this.height = 88,
    this.radius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _ShimmerPhase(
      builder: (context, phase) => _SkeletonBox(
        height: height,
        radius: radius,
        baseColor: cs.surfaceContainerHighest,
        phase: phase,
      ),
    );
  }
}

/// 骨架列表：n 张卡 + 12dp 间距，共用一道扫光（同一 _ShimmerPhase 下）。
class SkeletonList extends StatelessWidget {
  final int count;
  final double itemHeight;

  const SkeletonList({super.key, this.count = 3, this.itemHeight = 88});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _ShimmerPhase(
      builder: (context, phase) {
        return Column(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _SkeletonBox(
                height: itemHeight,
                radius: const BorderRadius.all(Radius.circular(12)),
                baseColor: cs.surfaceContainerHighest,
                phase: phase,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 骨架盒子：不透明底色 + 前景扫光渐变。
class _SkeletonBox extends StatelessWidget {
  final double height;
  final BorderRadius radius;
  final Color baseColor;
  final double phase;

  const _SkeletonBox({
    required this.height,
    required this.radius,
    required this.baseColor,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: baseColor, borderRadius: radius),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: _shimmerBegin,
          end: _shimmerEnd,
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: _shimmerPeakOpacity),
            Colors.transparent,
          ],
          stops: const [0.2, 0.5, 0.8],
          transform: _SlidingGradientTransform(phase),
        ),
      ),
    );
  }
}
