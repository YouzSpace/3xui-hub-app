import 'package:flutter/material.dart';

import '../theme/spacing.dart';
import 'motion.dart';

export 'skeleton.dart';

/// 状态视图（T1.14）：EmptyView / ErrorView。
///
/// 骨架屏（SkeletonCard/SkeletonList）在 [skeleton.dart]，这里 re-export。
/// 铁律：三态切换时只替换内容区，导航与底栏不动（由调用方保证）。
/// 所有动效时长/曲线只引用 [Motion] 常量。

/// 空状态：图标 + 一句话 + 一个 tonal 按钮，元素依次浮现（间隔 stagger）。
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyView({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <Widget>[
      Icon(icon, size: Sp.xxl + 16, color: cs.onSurfaceVariant),
      Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: cs.onSurfaceVariant),
      ),
      if (actionLabel != null)
        FilledButton.tonal(
          onPressed: onAction,
          child: Text(actionLabel!),
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

  @override
  void initState() {
    super.initState();
    // 这里不能读 MediaQuery：initState 期间依赖 InheritedWidget 会抛
    // 「dependOnInheritedWidgetOfExactType was called before initState()
    // completed」。放到首帧之后再做判断，行为不变。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _start();
    });
  }

  /// 首帧后启动：关闭动画则直接落到终态，否则按 index 依次浮现。
  void _start() {
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else {
      Future.delayed(Motion.stagger * widget.index, () {
        if (mounted) _controller.forward();
      });
    }
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

/// 错误状态：一句话 + 重试按钮（点击后按钮缩成转圈）。
class ErrorView extends StatefulWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  State<ErrorView> createState() => _ErrorViewState();
}

class _ErrorViewState extends State<ErrorView> {
  bool _loading = false;

  void _retry() {
    setState(() => _loading = true);
    widget.onRetry?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: Sp.xxl + 16, color: cs.error),
            const SizedBox(height: Sp.md),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: Sp.base),
            // 重试按钮缩成转圈（Motion.small，§3.2 #12）。
            AnimatedSwitcher(
              duration: Motion.small,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(Sp.sm),
                      child: SizedBox(
                        width: Sp.minTouch - Sp.sm,
                        height: Sp.minTouch - Sp.sm,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    )
                  : FilledButton.tonal(
                      key: const ValueKey('retry'),
                      onPressed: _retry,
                      child: const Text('重试'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
