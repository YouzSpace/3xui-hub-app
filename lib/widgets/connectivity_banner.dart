import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/spacing.dart';
import '../core/ui/motion.dart';
import '../providers/connectivity_banner_provider.dart';

/// 顶部连通性横幅（T9.3）：ping 失败时显示提示 + [重试]。
///
/// 用法（M2 登录页 / M5 首页）：
/// ```dart
/// Scaffold(
///   body: Column(children: [
///     const ConnectivityBanner(), // hidden 时收起为 0 高，不占位
///     Expanded(child: ...),
///   ]),
/// )
/// ```
/// 收起/展开用 AnimatedSize 过渡，不遮挡、不覆盖内容。
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectivityBannerProvider);
    final scheme = Theme.of(context).colorScheme;

    final Widget content;
    switch (state) {
      case ConnectivityState.hidden:
        content = const SizedBox.shrink();
      case ConnectivityState.checking:
        // 仅在横幅已展开（重试中）时显示加载态；首次 ping 不闪横幅。
        content = _buildRow(
          context,
          scheme: scheme,
          child: SizedBox(
            width: Sp.sm,
            height: Sp.sm,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.onErrorContainer,
            ),
          ),
        );
      case ConnectivityState.visible:
        content = _buildRow(
          context,
          scheme: scheme,
          child: TextButton(
            onPressed: () =>
                ref.read(connectivityBannerProvider.notifier).retry(),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onErrorContainer,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('重试'),
          ),
        );
    }

    return AnimatedSize(
      duration: Motion.small,
      curve: Motion.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: Motion.small,
        curve: state == ConnectivityState.hidden
            ? Motion.easeIn
            : Motion.easeOut,
        opacity: state == ConnectivityState.hidden ? 0 : 1,
        child: content,
      ),
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required ColorScheme scheme,
    required Widget child,
  }) {
    return Material(
      color: scheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.base,
            vertical: Sp.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.wifi_off, size: Sp.lg, color: scheme.onErrorContainer),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  '服务器暂时无法连接，请检查网络',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                ),
              ),
              const SizedBox(width: Sp.sm),
              child,
            ],
          ),
          // 横幅自身可以正常点 [重试]，周边内容不受影响。
        ),
      ),
    );
  }
}
