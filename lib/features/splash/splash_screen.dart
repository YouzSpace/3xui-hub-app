import 'package:flutter/material.dart';

import '../../core/ui/motion.dart';

/// 开屏过渡动画：居中加载转圈，停留片刻后整体淡出，完成后回调。
///
/// 不显示任何站名 / logo（客户 App 不暴露项目信息）；
/// 背景不透明，避免冷启动「白屏 → 内容浮现」的生硬感。
/// 由 app.dart 叠在路由之上，淡出后移除，露出首页 / 登录页。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.splash,
  );

  // 前段保持不透明（转圈持续），后段整体淡出。
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Motion.easeIn)),
      weight: 45,
    ),
  ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _opacity,
      child: ColoredBox(
        color: cs.surface,
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: cs.primary,
            ),
          ),
        ),
      ),
    );
  }
}
