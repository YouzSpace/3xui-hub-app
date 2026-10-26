import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import '../../data/models/plan.dart';
import '../../providers/auth_providers.dart';
import '../payment/payment_poller.dart';
import 'buy_sheet.dart';
import 'plan_card.dart';
import 'plans_provider.dart';
import 'plans_routes.dart';

/// 套餐页（T6.3）：AppBar「套餐」+ 右侧订单记录入口，列表为 PlanCard。
///
/// 购买闭环：
/// 1. 点「立即购买」→ 弹层（选支付方式 + 优惠码）→ `createOrder`
/// 2. 免费 / 后端直返 paid → 刷新用户套餐 + 提示，不跳支付页
/// 3. 有 pay_url → 跳 [PlansRoutes.payment]，由支付页负责轮询到账
class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('套餐'),
        actions: [
          IconButton(
            tooltip: '订单记录',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push(PlansRoutes.orders),
          ),
        ],
      ),
      body: plans.when(
        // 骨架屏放进可滚动容器：横屏 / 大字号下 3 张 180dp 卡会超出视口，
        // 直接放 Column 会 RenderFlex overflow（实测 600x800 测试面就溢出 52px）。
        loading: () => const SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          padding: EdgeInsets.all(Sp.base),
          child: SkeletonList(count: 3, itemHeight: 180),
        ),
        error: (e, _) => ErrorView(
          // 铁律：只展示 ApiException.message，不展示 e.toString()。
          message: e is ApiException ? e.message : '加载失败，请检查网络',
          onRetry: () => ref.invalidate(plansProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const _PlansEmpty();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(plansProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(Sp.base, Sp.base, Sp.base,
                  // 底栏浮在内容上（AppShell extendBody），留出玻璃高度。
                  Sp.xxl + Sp.base),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: Sp.md),
              itemBuilder: (context, i) {
                final plan = list[i];
                return PlanCard(
                  plan: plan,
                  onBuy: () => _onBuy(context, ref, plan),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _onBuy(
    BuildContext context,
    WidgetRef ref,
    Plan plan,
  ) async {
    final result = await BuySheet.show(context, plan);
    if (result == null) return; // 用户取消
    if (!context.mounted) return;

    // 免费套餐 / 后端直接判定已支付：不用进支付页，刷新套餐即可。
    if (result.isPaid) {
      await ref.read(userProvider.notifier).refresh();
      if (!context.mounted) return;
      _toast(context, '支付成功，套餐已到账');
      ref.invalidate(plansProvider);
      // 订单页缓存也过期了，下次进入重新拉。
      ref.invalidate(ordersProvider);
      return;
    }

    final payUrl = result.payUrl;
    if (payUrl == null || payUrl.isEmpty) {
      // 既不是 paid 又没有支付链接：后端异常（如通道配置坏了）。
      _toast(context, '获取支付链接失败，请稍后重试');
      return;
    }

    // 跳支付页；返回值由支付页写入结果（paid / timeout / closed）。
    final outcome = await context.push<PaymentOutcome>(
      PlansRoutes.payment,
      extra: PaymentArgs(
        orderNo: result.orderNo,
        payUrl: payUrl,
        amount: result.amount,
      ),
    );
    if (!context.mounted) return;
    // 支付页自己已经弹过提示；这里只做「缓存失效」这一件事，
    // 避免两处都弹导致同一条提示出现两次。
    if (outcome != null) {
      ref.invalidate(plansProvider);
      ref.invalidate(ordersProvider);
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 空状态（T6.3「暂无可用套餐」）。
///
/// 不用共享 `EmptyView`：它在 `_StaggerIn.initState()` 里调
/// `MediaQuery.of(context)`，Flutter 会直接抛「dependOnInheritedWidgetOfExactType
/// was called before initState completed」。M1 的公共组件不在 M6 的文件边界内，
/// 这里先自带一个同视觉（图标 + 一句话 + 淡入）的版本，汇总时再统一。
class _PlansEmpty extends StatelessWidget {
  const _PlansEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: Sp.xxl + 16, color: cs.onSurfaceVariant),
          const SizedBox(height: Sp.md),
          Text(
            '暂无可用套餐',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
