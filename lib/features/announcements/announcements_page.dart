import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import 'site_content_providers.dart';

/// 系统公告（独立页形态）。
///
/// 与首页横幅 [NoticeBanner] 共用同一份 site-config.announcement：
/// 横幅用来「提醒」，本页用来「完整阅读」。
class AnnouncementsPage extends ConsumerWidget {
  const AnnouncementsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(siteContentProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('系统公告')),
      body: site.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Sp.base),
          child: SkeletonList(count: 2),
        ),
        error: (e, _) => ErrorView(
          message: '公告加载失败，请稍后重试',
          onRetry: () => ref.invalidate(siteContentProvider),
        ),
        data: (content) {
          if (!content.hasAnnouncement) {
            return const EmptyView(
              icon: Icons.campaign_outlined,
              text: '暂无公告',
            );
          }
          final textTheme = Theme.of(context).textTheme;
          final cs = Theme.of(context).colorScheme;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Sp.base),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Sp.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最新公告', style: textTheme.titleMedium),
                    const SizedBox(height: Sp.md),
                    SelectableText(
                      content.announcement.trim(),
                      style: textTheme.bodyLarge
                          ?.copyWith(height: 1.7, color: cs.onSurface),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
