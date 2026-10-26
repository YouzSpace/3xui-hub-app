import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';
import '../../data/models/node.dart';
import 'node_display.dart';

/// 节点列表项（T3.5）。
///
/// 布局（56–72dp，取 64dp）：左状态圆点 / 中名称 + 协议地址 / 右延迟徽章。
/// 点击选中，长按只测速这一个节点。
/// 列表项是内容区，禁止玻璃材质（ui-glass-motion §2.1），用 MD3 色阶。
class NodeTile extends StatelessWidget {
  final Node node;
  final bool selected;

  /// 已连接且就是当前节点（圆点用 primary 实心 + 额外内环区分）。
  final bool connected;
  final bool measuring;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const NodeTile({
    super.key,
    required this.node,
    required this.selected,
    required this.connected,
    required this.measuring,
    required this.onTap,
    required this.onLongPress,
  });

  static const double _height = 64;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;

    // 卡片：选中 secondaryContainer 高亮 + primary 边框；未选中跟 cardTheme 一致。
    final bg = selected
        ? cs.secondaryContainer.withValues(alpha: 0.5)
        : (theme.brightness == Brightness.light
              ? cs.surfaceContainerLowest
              : cs.surfaceContainerLow);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _height),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Sp.md,
                vertical: Sp.sm,
              ),
              child: Row(
                children: [
                  _StatusDot(selected: selected, connected: connected),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayNodeName(node),
                          style: textTheme.titleMedium,
                          // 1 行省略（T3.5）。
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayNodeSubtitle(node),
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  LatencyBadge(latencyMs: node.latencyMs, measuring: measuring),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 状态圆点：当前选中 → primary 实心；已连接再叠一圈内环；其他 outlineVariant。
class _StatusDot extends StatelessWidget {
  final bool selected;
  final bool connected;

  const _StatusDot({required this.selected, required this.connected});

  static const double _size = Sp.md;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: connected ? '已连接' : (selected ? '已选中' : '未选中'),
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? cs.primary : Colors.transparent,
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: 2,
          ),
        ),
        child: connected
            ? Center(
                child: Container(
                  width: Sp.xs,
                  height: Sp.xs,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.onPrimary,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
