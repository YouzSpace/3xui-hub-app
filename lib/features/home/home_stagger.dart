import 'package:flutter/material.dart';

import '../../core/ui/motion.dart';

/// 首页各区块的浮现（§3.2 #1：分块浮现，间隔 [Motion.stagger]）。
///
/// 系统「移除动画」时直接显示终态。
class HomeStagger extends StatefulWidget {
  const HomeStagger({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<HomeStagger> createState() => _HomeStaggerState();
}

class _HomeStaggerState extends State<HomeStagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.small,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // MediaQuery 只能在 initState 之后读（这里读一次即可）。
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
      return;
    }
    Future<void>.delayed(Motion.stagger * widget.index, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Motion.easeOut);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 8 * (1 - curved.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
