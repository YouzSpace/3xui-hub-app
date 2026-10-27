import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/spacing.dart';
import '../../data/models/node.dart';

/// 节点行的展示逻辑（纯函数，方便单测）。
///
/// 设计规范（design-tokens §8）禁止界面文本出现 emoji，但后端节点名
/// 会带国旗（`server/internal/subscription/region.go` 生成 `🇭🇰` 之类）。
/// 所以显示前统一过滤：剥掉 emoji 与零宽连接符，再收拢空白。

/// emoji 相关码位：旗帜/图形符号/杂项符号/变体选择符/零宽连接符/标签字符。
final RegExp _emoji = RegExp(
  '['
  '\u{1F000}-\u{1FAFF}' // 麻将、扑克、区域指示符（国旗）、各类 pictograph
  '\u{2600}-\u{27BF}' // 杂项符号 + Dingbats
  '\u{2B00}-\u{2BFF}' // 杂项符号与箭头（含 ⬛ 之类）
  '\u{3030}\u{303D}\u{3297}\u{3299}' // CJK 兼容的 emoji 字符
  '\u{FE0E}\u{FE0F}' // 变体选择符
  '\u{200D}' // 零宽连接符（组合 emoji）
  '\u{20E3}' // keycap 组合符
  '\u{E0020}-\u{E007F}' // 标签字符（英格兰旗等）
  ']',
  unicode: true,
);

/// 连续空白（含全角空格）。
final RegExp _spaces = RegExp(r'[\s　]+');

/// 过滤 emoji 并整理空白；过滤后为空返回 [fallback]。
String displayNodeName(Node node) {
  final text = node.name
      .replaceAll(_emoji, '')
      .replaceAll(_spaces, ' ')
      // 剥掉 emoji 后可能留下开头/结尾的分隔符（`🇭🇰 香港 01` → ` 香港 01`）。
      .replaceAll(RegExp(r'^[\s\-–—:：·|/]+|[\s\-–—:：·|/]+$'), '');
  return text.isEmpty ? node.address : text;
}

/// 第二行：`vless · host:port`（协议统一大写显示更整齐）。
String displayNodeSubtitle(Node node) =>
    '${node.protocol.toUpperCase()} · ${node.address}';

/// 延迟徽章文案：未测速 `—`，测速超时 `超时`，否则 `123 ms`。
String latencyLabel(int? latencyMs) {
  if (latencyMs == null) return '—';
  if (latencyMs < 0) return '超时';
  return '$latencyMs ms';
}

/// 延迟档位文案（无障碍朗读 / Tooltip 用）。
String latencySemantics(int? latencyMs) {
  if (latencyMs == null) return '未测速';
  if (latencyMs < 0) return '测速超时';
  if (latencyMs < 100) return '延迟 $latencyMs 毫秒，良好';
  if (latencyMs < 200) return '延迟 $latencyMs 毫秒，一般';
  return '延迟 $latencyMs 毫秒，较差';
}

/// 延迟徽章颜色：<100 绿 / <200 橙 / 其他红 / 未测或超时 onSurfaceVariant。
///
/// 绿/橙取 design-tokens §1.4 的连接状态色（不占 M3 角色），红用 `error`。
Color latencyColor(BuildContext context, int? latencyMs) {
  final cs = Theme.of(context).colorScheme;
  if (latencyMs == null || latencyMs < 0) return cs.onSurfaceVariant;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (latencyMs < 100) {
    return dark ? AppTheme.connectedDark : AppTheme.connectedLight;
  }
  if (latencyMs < 200) {
    return dark ? AppTheme.connectingDark : AppTheme.connectingLight;
  }
  return cs.error;
}

/// 延迟徽章：等宽数字 + 圆角胶囊底（8% 主题色）。
class LatencyBadge extends StatelessWidget {
  final int? latencyMs;

  /// 正在测速时显示转圈，占位宽度不变（避免列表横向跳动）。
  final bool measuring;

  const LatencyBadge({
    super.key,
    required this.latencyMs,
    this.measuring = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = latencyColor(context, latencyMs);
    return Semantics(
      label: measuring ? '正在测速' : latencySemantics(latencyMs),
      child: Container(
        width: Sp.xxl + Sp.base,
        height: Sp.xl - Sp.xs,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: measuring
            ? SizedBox(
                width: Sp.md + 2,
                height: Sp.md + 2,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              )
            : Text(
                latencyLabel(latencyMs),
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
      ),
    );
  }
}
