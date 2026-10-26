import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/spacing.dart';
import '../announcements/site_content_providers.dart';
import 'feedback_launcher.dart';

/// 设置页「意见反馈」行（T7.4）。
///
/// 由 M8 的设置页直接嵌进列表：`feedback_link` 为空时返回
/// `SizedBox.shrink()`，不占位；非空才出现。
class FeedbackEntry extends ConsumerWidget {
  const FeedbackEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(siteContentProvider).valueOrNull?.feedbackLink ?? '';
    if (link.trim().isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => _onTap(context, link),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.base,
            vertical: Sp.md,
          ),
          child: Row(
            children: [
              Icon(Icons.feedback_outlined, color: cs.onSurfaceVariant),
              const SizedBox(width: Sp.base),
              Expanded(
                child: Text(
                  '意见反馈',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Icon(Icons.open_in_new, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context, String link) async {
    final ok = await openFeedbackLink(link);
    if (ok || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('无法打开链接')));
  }
}
