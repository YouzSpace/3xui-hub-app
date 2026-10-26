import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../providers/auth_providers.dart';
import 'settings_providers.dart';
import 'settings_tiles.dart';

/// 协议切换（T8.1 账号分组，仅站点支持多协议时出现）。
///
/// 切换代价高（后端要 attach 新 inbound + detach 旧 inbound），
/// 所以必须二次确认，成功后清订阅缓存并重拉。
class ProtocolSwitchTile extends ConsumerWidget {
  const ProtocolSwitchTile({super.key, required this.current});

  final String current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return SettingsTile(
      title: '协议切换',
      subtitle: '当前 ${protocolLabel(current)}，切换后需重新获取节点',
      icon: Icons.swap_horiz,
      trailing: Text(
        protocolLabel(current),
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: cs.onSurfaceVariant),
      ),
      onTap: () => _confirmAndSwitch(context, ref),
    );
  }

  Future<void> _confirmAndSwitch(BuildContext context, WidgetRef ref) async {
    final alternatives = protocolAlternatives(current);
    if (alternatives.isEmpty) return;
    final target = alternatives.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('切换协议'),
        content: Text(
          '将切换到 ${protocolLabel(target)}。切换会重建所有节点的该账号客户端，'
          '完成后需要重新获取节点列表。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('切换到 ${protocolLabel(target)}'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(settingsRepositoryProvider).switchProtocol(target);
    } on ApiException catch (e) {
      // 后端 msg 已是中文可展示文案（含「不支持的协议」「切换失败」等）。
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('协议切换失败，请稍后重试')));
      return;
    }

    // 协议变了 → 旧订阅配置全部失效（system-design §4.4）：
    // ① 清订阅缓存 ② 重拉 /api/me 拿新 protocol ③ 重拉订阅节点。
    await ref.read(subscriptionCacheClearerProvider)();
    await ref.read(userProvider.notifier).refresh();

    final refreshNodes = ref.read(subscriptionRefresherProvider);
    if (refreshNodes != null) {
      try {
        await refreshNodes();
      } catch (_) {
        // 节点重拉失败不影响「协议已切换」，节点页自己会报错并提供重试。
      }
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            refreshNodes == null
                ? '已切换到 ${protocolLabel(target)}，请到节点页重新获取'
                : '已切换到 ${protocolLabel(target)}，节点已重新获取',
          ),
        ),
      );
  }
}
