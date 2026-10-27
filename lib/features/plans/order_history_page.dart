import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import '../../data/models/order.dart';
import '../payment/payment_poller.dart';
import '../payment/payment_webview_page.dart';
import 'plans_provider.dart';
import 'plans_routes.dart';
import '../../core/ui/app_toast.dart';

/// 订单记录（T6.6）。
///
/// 后端只回最近 20 笔（`handlePaymentOrders`），所以这里不做分页。
/// 待支付订单可「继续支付」：`retryPay` 拿新 pay_url → 支付页 → 轮询到账。
class OrderHistoryPage extends ConsumerStatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  ConsumerState<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends ConsumerState<OrderHistoryPage> {
  /// 正在续付的订单号（同一时刻只允许一笔，防连点）。
  String? _retrying;

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('订单记录'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(ordersProvider),
          ),
        ],
      ),
      body: orders.when(
        // 同套餐页：骨架屏可滚动，避免小视口 RenderFlex overflow。
        loading: () => const SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          padding: EdgeInsets.all(Sp.base),
          child: SkeletonList(count: 4, itemHeight: 108),
        ),
        error: (e, _) => ErrorView(
          message: e is ApiException ? e.message : '加载失败，请检查网络',
          onRetry: () => ref.invalidate(ordersProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return _OrdersEmpty(onBrowse: () => context.go(PlansRoutes.plans));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(ordersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(Sp.base),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: Sp.md),
              itemBuilder: (context, i) {
                final order = list[i];
                return _OrderTile(
                  order: order,
                  retrying: _retrying == order.orderNo,
                  onRetry: order.canRetry && _retrying == null
                      ? () => _retryPay(order)
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _retryPay(Order order) async {
    setState(() => _retrying = order.orderNo);
    try {
      final result =
          await ref.read(orderRepositoryProvider).retryPay(order.orderNo);
      if (!mounted) return;
      final outcome = await context.push<PaymentOutcome>(
        PlansRoutes.payment,
        extra: PaymentPageArgs(
          orderNo: result.orderNo,
          payUrl: result.payUrl,
          amount: order.amount,
        ),
      );
      if (!mounted) return;
      if (outcome != null) ref.invalidate(ordersProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      // 410「支付链接已失效，请返回商城重新下单」已由后端给出可直接展示的文案。
      showAppToast(context, e.message);
      // 410 时后端已把该单作废，重新拉一次列表让状态跟着变。
      ref.invalidate(ordersProvider);
    } finally {
      if (mounted) setState(() => _retrying = null);
    }
  }
}

/// 单个订单：订单号（可点复制）/ 套餐名 / 金额 / 状态徽章 / 创建时间。
class _OrderTile extends StatelessWidget {
  final Order order;
  final bool retrying;
  final VoidCallback? onRetry;

  const _OrderTile({
    required this.order,
    required this.retrying,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Sp.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.planName.isEmpty ? '—' : order.planName,
                    style: textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusBadge(status: order.status),
              ],
            ),
            const SizedBox(height: Sp.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  order.amount.display,
                  style: textTheme.headlineSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDateTime(order.createdAt),
                  style: textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: Sp.xs),
            // 订单号：整行可点复制（长按也可选中），避免为一行字单独放按钮。
            InkWell(
              onTap: () => _copyOrderNo(context),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Sp.xs),
                child: Row(
                  children: [
                    Text(
                      '订单号',
                      style: textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: Text(
                        order.orderNo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Icon(Icons.copy_all_outlined,
                        size: 16, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            if (order.canRetry) ...[
              const SizedBox(height: Sp.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onRetry,
                  child: retrying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('继续支付'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _copyOrderNo(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: order.orderNo));
    if (!context.mounted) return;
    showAppToast(context, '订单号已复制');
  }

  /// `2026-10-26 14:05`；时间为 null 时 `—`。
  static String _formatDateTime(DateTime? d) {
    if (d == null) return '—';
    final t = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// 状态徽章：已支付用 primaryContainer，待支付用 tertiaryContainer
/// （等用户动作），已关闭用 surfaceContainerHighest（不需要动作）。
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      OrderStatus.paid => (cs.primaryContainer, cs.onPrimaryContainer),
      OrderStatus.pending => (cs.tertiaryContainer, cs.onTertiaryContainer),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        OrderStatus.label(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

/// 空状态（T6.6）。
///
/// 与套餐页同理不用共享 `EmptyView`（它在 `initState` 里读 MediaQuery 会抛断言）。
/// 结构照 EmptyView：图标 + 一句话 + 一个 tonal 按钮。
class _OrdersEmpty extends StatelessWidget {
  final VoidCallback onBrowse;

  const _OrdersEmpty({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: Sp.xxl + 16, color: cs.onSurfaceVariant),
          const SizedBox(height: Sp.md),
          Text(
            '还没有订单记录',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: Sp.base),
          FilledButton.tonal(
            onPressed: onBrowse,
            child: const Text('去看看套餐'),
          ),
        ],
      ),
    );
  }
}
