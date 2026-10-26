import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/motion.dart';

/// 节点页空状态（「当前没有可用节点」+ 「重新获取」）。
///
/// 不用共享 `EmptyView`：它在 `_StaggerIn.initState()` 里调
/// `MediaQuery.of(context)`，Flutter 会直接抛
/// 「dependOnInheritedWidgetOfExactType was called before initState completed」。
/// `lib/core/ui/` 是公共文件（并行期间禁止改），这里自带一个同视觉
/// （图标 + 一句话 + tonal 按钮，依次淡入上移）的实现，汇总时再统一。
class NodesEmptyView extends StatelessWidget {
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  const NodesEmptyView({
    super.key,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final items = <Widget>[
      Icon(Icons.dns_outlined, size: Sp.xxl + 16, color: cs.onSurfaceVariant),
      Text(
        text,
        textAlign: TextAlign.center,
        style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      ),
      FilledButton.tonal(
        onPressed: onAction,
        child: Text(actionLabel),
      ),
    ];

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: Sp.md),
            _StaggerIn(index: i, child: items[i]),
          ],
        ],
      ),
    );
  }
}

/// 依次浮现：index * stagger 延迟 + 淡入上移；关闭动画时直接显示。
///
/// 与 `core/ui/state_views.dart` 的同名私有实现等价，唯一区别是
/// 在 `didChangeDependencies` 里读 `MediaQuery`（不在 initState 里读）。
class _StaggerIn extends StatefulWidget {
  final int index;
  final Widget child;

  const _StaggerIn({required this.index, required this.child});

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn>
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
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
      return;
    }
    Future.delayed(Motion.stagger * widget.index, () {
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
