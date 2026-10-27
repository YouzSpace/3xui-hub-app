import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/tutorial.dart';
import 'tutorial_grouping.dart';
import 'tutorial_providers.dart';

/// 使用教程列表（T7.2）：按 category 分组，点条目进详情。
class TutorialsPage extends ConsumerWidget {
  const TutorialsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tutorials = ref.watch(tutorialsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('使用教程')),
      body: tutorials.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Sp.base),
          child: SkeletonList(count: 3),
        ),
        error: (e, _) => ErrorView(
          message: tutorialErrorText(e),
          onRetry: () => ref.read(tutorialsProvider.notifier).refresh(),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.menu_book_outlined,
              text: '暂无教程',
            );
          }
          final groups = groupTutorials(list);
          return RefreshIndicator(
            onRefresh: () => ref.read(tutorialsProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(Sp.base),
              children: [
                for (final group in groups) ...[
                  _GroupSection(group: group),
                  const SizedBox(height: Sp.md),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 一个分类：分类标题 + 条目（分类标题不用 ExpansionTile，
/// 教程通常只有几条，展开收起反而多一次点击）。
class _GroupSection extends StatelessWidget {
  final TutorialGroup group;

  const _GroupSection({required this.group});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Sp.xs, bottom: Sp.sm),
          child: Text(
            group.category,
            style: textTheme.titleSmall?.copyWith(color: cs.primary),
          ),
        ),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < group.items.length; i++) ...[
                if (i > 0) const Divider(indent: Sp.base, endIndent: Sp.base),
                _TutorialTile(tutorial: group.items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TutorialTile extends StatelessWidget {
  final Tutorial tutorial;

  const _TutorialTile({required this.tutorial});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => context.push('/tutorials/${tutorial.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.base,
            vertical: Sp.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tutorial.title,
                      style: textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Sp.xs),
                    Text(
                      formatDate(tutorial.createdAt),
                      style: textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
