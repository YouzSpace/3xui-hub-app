import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import '../announcements/site_content_providers.dart';
import 'invite_code_card.dart';
import 'invite_providers.dart';
import 'redeem_code_list.dart';

/// 邀请有礼（T7.1）。
///
/// 两路数据各自独立：邀请码失败只影响信息卡，兑换码区照常显示；
/// 站点名（分享文案）失败退化成「本服务」，不阻塞邀请码展示。
class InvitePage extends ConsumerWidget {
  const InvitePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invite = ref.watch(inviteInfoProvider);
    final site = ref.watch(siteContentProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('邀请有礼')),
      body: invite.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Sp.base),
          child: SkeletonList(count: 2),
        ),
        error: (e, _) => ErrorView(
          message: inviteErrorText(e),
          onRetry: () => ref.read(inviteInfoProvider.notifier).refresh(),
        ),
        data: (info) => RefreshIndicator(
          onRefresh: () => ref.read(inviteInfoProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.base, Sp.base, Sp.base, Sp.xxl),
            children: [
              InviteCodeCard(
                code: info.code,
                invitedCount: info.invitedCount,
                siteTitle: site.valueOrNull?.siteTitle ?? '',
                onRetry: () =>
                    ref.read(inviteInfoProvider.notifier).refresh(),
              ),
              const SizedBox(height: Sp.lg),
              RedeemCodeList(codes: info.redeemCodes),
            ],
          ),
        ),
      ),
    );
  }
}
