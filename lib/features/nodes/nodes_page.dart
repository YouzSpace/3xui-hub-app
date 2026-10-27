import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import '../../data/models/node.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_state.dart';
import '../shell/app_shell.dart';
import 'node_tile.dart';
import 'nodes_empty_view.dart';
import 'nodes_provider.dart';
import '../../core/ui/app_toast.dart';

/// 节点列表页（T3.5）。
///
/// AppBar「节点」+ 右侧 [刷新] + [自动选择 Switch]；列表项见 [NodeTile]。
/// - 点击 → 选中；已连接时先确认再断开重连；
/// - 长按 → 只测速这个节点；
/// - 下拉刷新 → 重新拉订阅。
class NodesPage extends ConsumerWidget {
  const NodesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = ref.watch(nodesProvider);
    final autoSelect = ref.watch(autoSelectFastestProvider);
    final measuring = ref.watch(measuringNodesProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('节点'),
        actionsPadding: const EdgeInsets.only(right: Sp.sm),
        actions: [
          if (nodes is AsyncData<List<Node>> && nodes.value.isNotEmpty)
            _AutoSelectSwitch(
              value: autoSelect,
              onChanged: (v) =>
                  ref.read(nodesProvider.notifier).setAutoSelectFastest(v),
            ),
          IconButton(
            tooltip: '刷新订阅',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(context, ref),
          ),
        ],
      ),
      // 右下角闪电悬浮按钮：一键测全部节点真延迟（参考图样式：圆角矩形无文字）。
      // 测速中隐藏一键测速按钮（像 fclash），测速完成再恢复，避免按钮转圈占位。
      floatingActionButton:
          nodes.valueOrNull?.isNotEmpty == true && measuring.isEmpty
              ? Padding(
                  padding: EdgeInsets.only(bottom: appBottomBarHeight),
                  child: FloatingActionButton(
                    tooltip: '一键测速',
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Sp.base),
                    ),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    onPressed: () =>
                        ref.read(nodesProvider.notifier).measureAll(),
                    child: const Icon(Icons.bolt),
                  ),
                )
              : null,
      body: nodes.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Sp.base),
          child: SkeletonList(count: 6, itemHeight: 64),
        ),
        error: (e, _) => ErrorView(
          // 铁律：只展示 ApiException.message，不展示 e.toString()。
          message: e is ApiException ? e.message : '加载失败，请检查网络',
          onRetry: () => ref.read(nodesProvider.notifier).refresh(),
        ),
        data: (list) {
          if (list.isEmpty) {
            return NodesEmptyView(
              text: '当前没有可用节点',
              actionLabel: '重新获取',
              onAction: () => ref.read(nodesProvider.notifier).refresh(),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(nodesProvider.notifier).refresh(),
            child: _NodeList(nodes: list),
          );
        },
      ),
    );
  }

  /// AppBar 刷新按钮：拉订阅并给出结果提示（下拉刷新靠指示器，不用 toast）。
  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(nodesProvider.notifier);
    await notifier.refresh();
    if (!context.mounted) return;
    final state = ref.read(nodesProvider);
    final message = state.hasError
        ? (state.error is ApiException
              ? (state.error as ApiException).message
              : '订阅获取失败，请稍后重试')
        : '已更新 ${state.valueOrNull?.length ?? 0} 个节点';
    showAppToast(context, message);
  }
}

/// 列表本体：单独一层，避免整个页面跟着选中态重建。
class _NodeList extends ConsumerWidget {
  final List<Node> nodes;

  const _NodeList({required this.nodes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedNodeProvider);
    final measuring = ref.watch(measuringNodesProvider);
    final vpn = ref.watch(vpnProvider);
    final connected = vpn.status == VpnStatus.connected;
    final activeRaw = connected ? vpn.activeNode?.raw : null;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        Sp.base,
        Sp.sm,
        Sp.base,
        // 底栏浮在内容上（AppShell extendBody），底部留出底栏视觉高度 + 系统安全区。
        appBottomBarHeight + MediaQuery.of(context).padding.bottom + Sp.base,
      ),
      itemCount: nodes.length,
      separatorBuilder: (_, _) => const SizedBox(height: Sp.sm),
      itemBuilder: (context, i) {
        final node = nodes[i];
        return NodeTile(
          node: node,
          selected: selected?.raw == node.raw,
          connected: activeRaw == node.raw,
          measuring: measuring.contains(node.raw),
          onTap: () => _onTap(context, ref, node),
          onLongPress: () => _measureOne(context, ref, node),
        );
      },
    );
  }

  /// 点击：先选中（并持久化）；已连接时确认后断开重连到新节点。
  Future<void> _onTap(BuildContext context, WidgetRef ref, Node node) async {
    await ref.read(nodesProvider.notifier).select(node);
    // 用户手动选节点 → 关闭自动选择（之后连接用手动选的节点）。
    await ref.read(autoSelectFastestProvider.notifier).set(false);
    if (!context.mounted) return;

    final vpn = ref.read(vpnProvider);
    if (vpn.isBusy) {
      _toast(context, '正在连接，请稍候');
      return;
    }
    if (vpn.status != VpnStatus.connected) {
      // 未连接：只记选中态，连接由首页大按钮触发。
      return;
    }
    if (vpn.activeNode?.raw == node.raw) return; // 已连的就是它

    final confirmed = await _confirmSwitch(context);
    if (confirmed != true || !context.mounted) return;

    final controller = ref.read(vpnProvider.notifier);
    await controller.disconnect();
    if (!context.mounted) return;
    await controller.connect(node);
    if (!context.mounted) return;

    final next = ref.read(vpnProvider);
    _toast(
      context,
      next.status == VpnStatus.error
          ? (next.errorMessage ?? '连接失败，请稍后重试')
          : '正在连接到 ${node.name}',
    );
  }

  Future<void> _measureOne(
    BuildContext context,
    WidgetRef ref,
    Node node,
  ) async {
    await ref.read(nodesProvider.notifier).measureOne(node);
    if (!context.mounted) return;
    final updated = ref
        .read(nodesProvider)
        .valueOrNull
        ?.where((n) => n.raw == node.raw)
        .firstOrNull;
    final ms = updated?.latencyMs;
    _toast(context, ms == null ? '测速失败，请稍后重试' : '延迟 $ms ms');
  }

  /// 切换节点二次确认（T3.5 文案）。
  Future<bool?> _confirmSwitch(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('切换节点'),
        content: const Text('切换节点会断开重连，继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    showAppToast(context, message);
  }
}

/// AppBar 里的「自动选择」开关：文字标签 + Switch（标题栏高度内放得下）。
class _AutoSelectSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AutoSelectSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '自动选择',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
