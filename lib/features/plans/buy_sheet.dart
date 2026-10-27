import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/spacing.dart';
import '../../core/ui/glass_surface.dart';
import '../../core/ui/state_views.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/money.dart';
import '../../data/models/order.dart';
import '../../data/models/pay_method.dart';
import '../../data/models/plan.dart';
import 'plans_provider.dart';
import '../../core/ui/app_toast.dart';

/// 购买弹层（T6.3）：选支付方式（RadioListTile）+ 优惠码（含「验证」）+
/// 最终金额 + 「去支付」→ `createOrder` → 跳支付页。
///
/// 玻璃白名单内（底部面板）：GlassSurface + 顶部 28dp 圆角 + 拖拽指示条。
/// 弹层内组件不读 `ProviderScope` 之外的全局状态，也不缓存订单号 ——
/// 每次「去支付」都真实建单（后端自己有 1 分钟防连点 + 旧 pending 单复用）。
class BuySheet extends ConsumerStatefulWidget {
  final Plan plan;

  const BuySheet({super.key, required this.plan});

  /// 打开弹层并返回下单结果（null = 用户取消）。
  ///
  /// 调用方拿到结果后负责跳支付页 / 提示免费到账。
  static Future<CreateOrderResult?> show(
    BuildContext context,
    Plan plan,
  ) {
    return showModalBottomSheet<CreateOrderResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (_) => BuySheet(plan: plan),
    );
  }

  @override
  ConsumerState<BuySheet> createState() => _BuySheetState();
}

class _BuySheetState extends ConsumerState<BuySheet> {
  /// 当前选中的支付方式 id（后端 `payment_config_id`）。
  int? _methodId;

  final _discountController = TextEditingController();
  DiscountResult? _discount;
  bool _checkingDiscount = false;

  /// 正在建单（按钮转圈并禁用，防连点）。
  bool _submitting = false;

  /// 自动选中默认支付方式的监听句柄（dispose 里必须关，否则泄漏）。
  ProviderSubscription<AsyncValue<List<PayMethod>>>? _methodsSub;

  @override
  void initState() {
    super.initState();
    // 支付方式到了自动选中第一个（最多 3 个，无需额外交互）。
    _methodsSub = ref.listenManual(payMethodsProvider, (_, next) {
      final methods = next.valueOrNull;
      if (!mounted || methods == null || methods.isEmpty) return;
      if (_methodId == null) setState(() => _methodId = methods.first.id);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _methodsSub?.close();
    _discountController.dispose();
    super.dispose();
  }

  Plan get _plan => widget.plan;

  /// 最终金额：有确定折后价用它，否则用原价（真实金额以建单返回为准）。
  int get _finalCents {
    final discounted = _discount?.finalAmount;
    if (_discount?.usable == true && discounted != null) {
      return discounted.cents;
    }
    return _plan.price.cents;
  }

  bool get _hasConfirmedDiscount =>
      _discount?.usable == true && _discount!.hasFinalAmount;

  Future<void> _checkDiscount() async {
    final code = _discountController.text.trim();
    if (code.isEmpty) {
      setState(() => _discount = DiscountResult.invalid('请输入优惠码'));
      return;
    }
    setState(() => _checkingDiscount = true);
    try {
      final result = await ref
          .read(orderRepositoryProvider)
          .checkDiscount(code, _plan.id);
      if (!mounted) return;
      setState(() => _discount = result);
    } on ApiException catch (e) {
      // 只剩 429 会走到这里（其它失败已归一成 usable=false）。
      if (!mounted) return;
      setState(() => _discount = DiscountResult.invalid(e.message));
    } finally {
      if (mounted) setState(() => _checkingDiscount = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await ref.read(orderRepositoryProvider).createOrder(
            planId: _plan.id,
            methodId: _methodId,
            discountCode: _discountController.text.trim().isEmpty
                ? null
                : _discountController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      if (!mounted) return;
      // 429 / 400（套餐下架、折后不足 1 元…）后端 msg 已可直接展示。
      showAppToast(context, e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final methods = ref.watch(payMethodsProvider);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      // 键盘顶起弹层（优惠码输入框获得焦点时）。
      padding: EdgeInsets.only(bottom: bottomInset),
      child: GlassSurface(
        radius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Sp.base, Sp.sm, Sp.base, Sp.base),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: Sp.base),
                Text('购买 ${_plan.name}', style: textTheme.titleMedium),
                const SizedBox(height: Sp.base),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SpecSummary(plan: _plan),
                        const SizedBox(height: Sp.base),
                        Text('支付方式', style: textTheme.labelLarge),
                        const SizedBox(height: Sp.xs),
                        _MethodsSection(
                          methods: methods,
                          selectedId: _methodId,
                          onChanged: (id) => setState(() => _methodId = id),
                          onRetry: () => ref.invalidate(payMethodsProvider),
                        ),
                        if (_plan.price.cents > 0) ...[
                          const SizedBox(height: Sp.base),
                          Text('优惠码', style: textTheme.labelLarge),
                          const SizedBox(height: Sp.xs),
                          _DiscountSection(
                            controller: _discountController,
                            checking: _checkingDiscount,
                            result: _discount,
                            onCheck: _checkDiscount,
                            onChanged: () {
                              if (_discount != null) {
                                setState(() => _discount = null);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: Sp.lg * 2),
                _PriceRow(
                  plan: _plan,
                  finalCents: _finalCents,
                  showOriginal: _hasConfirmedDiscount,
                ),
                const SizedBox(height: Sp.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_plan.price.cents == 0 ? '免费领取' : '去支付'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 规格摘要：纯第三方只写线路 + 有效期，否则写流量 + 有效期。
class _SpecSummary extends StatelessWidget {
  final Plan plan;

  const _SpecSummary({required this.plan});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rows = <(String, String, String)>[];
    if (plan.isPureThirdParty) {
      rows.add(('线路', '第三方高速线路', '不限速'));
      rows.add(('有效期', '${plan.months} 个月', '到期后需续费'));
    } else if (plan.isPeriod) {
      final traffic = plan.monthlyTraffic ?? 0;
      rows.add(('流量', traffic > 0 ? formatBytes(traffic) : '不限量', '每月重置'));
      rows.add(('有效期', '${plan.months} 个月', '到期后需续费'));
    } else {
      final traffic = plan.totalTraffic ?? 0;
      rows.add(('流量', traffic > 0 ? formatBytes(traffic) : '不限量', '用完为止'));
      rows.add(('有效期', '永久', '不限时间'));
    }
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    row.$1,
                    style: textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                Text(row.$2, style: textTheme.bodyMedium),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    row.$3,
                    textAlign: TextAlign.right,
                    style: textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 根据支付方式名返回品牌图标资源路径；非微信/支付宝返回 null。
String? _payIcon(String name) {
  if (name.contains('微信')) return 'assets/pay/wx_pay.png';
  if (name.contains('支付宝')) return 'assets/pay/ali_pay.png';
  return null;
}

/// 支付方式单选：RadioGroup + RadioListTile（M3 当前 API，不用已弃用的 groupValue）。
class _MethodsSection extends StatelessWidget {
  final AsyncValue<List<PayMethod>> methods;
  final int? selectedId;
  final ValueChanged<int> onChanged;

  /// 加载失败时的重试：重新拉 `payMethodsProvider`（不是空实现）。
  final VoidCallback onRetry;

  const _MethodsSection({
    required this.methods,
    required this.selectedId,
    required this.onChanged,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return methods.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: Sp.base),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => ErrorView(
        message: e is ApiException ? e.message : '支付方式加载失败',
        onRetry: onRetry,
      ),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.base),
            child: Text(
              '站点暂未开启在线支付，请联系管理员',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        return RadioGroup<int>(
          groupValue: selectedId,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          child: Column(
            children: [
              for (final m in list)
                Builder(builder: (_) {
                  final icon = _payIcon(m.name);
                  return RadioListTile<int>(
                    value: m.id,
                    title: icon == null
                        ? Text(m.name)
                        : Row(
                            children: [
                              Image.asset(icon, width: 20, height: 20),
                              const SizedBox(width: Sp.sm),
                              Expanded(child: Text(m.name)),
                            ],
                          ),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

/// 优惠码：输入框 + 「验证」按钮；结果直接跟在下方一行。
class _DiscountSection extends StatelessWidget {
  final TextEditingController controller;
  final bool checking;
  final DiscountResult? result;
  final VoidCallback onCheck;
  final VoidCallback onChanged;

  const _DiscountSection({
    required this.controller,
    required this.checking,
    required this.result,
    required this.onCheck,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usable = result?.usable == true;
    final message = result?.message ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !checking,
                textCapitalization: TextCapitalization.characters,
                maxLength: 32,
                decoration: const InputDecoration(
                  hintText: '输入邀请码 / 兑换码',
                  counterText: '',
                  isDense: true,
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: Sp.sm),
            SizedBox(
              height: Sp.minTouch,
              child: FilledButton.tonal(
                onPressed: checking ? null : onCheck,
                child: checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('验证'),
              ),
            ),
          ],
        ),
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: Row(
              children: [
                Icon(
                  usable ? Icons.check_circle_outline : Icons.info_outline,
                  size: 16,
                  color: usable ? cs.primary : cs.error,
                ),
                const SizedBox(width: Sp.xs),
                Expanded(
                  child: Text(
                    usable && result?.rate != null
                        ? '$message（${_rateLabel(result!.rate!)}）'
                        : message,
                    style: textTheme.bodySmall
                        ?.copyWith(color: usable ? cs.primary : cs.error),
                  ),
                ),
              ],
            ),
          ),
        if (usable && result?.note != null && result!.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: Text(
              result!.note,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  /// 0.90 → `9 折`；0.85 → `8.5 折`。
  static String _rateLabel(double rate) {
    final tenths = rate * 10;
    final rounded = (tenths * 10).round() / 10;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
    return '$text 折';
  }
}

/// 底部金额区：折后价 + 划线原价 + 「已优惠」。
class _PriceRow extends StatelessWidget {
  final Plan plan;
  final int finalCents;
  final bool showOriginal;

  const _PriceRow({
    required this.plan,
    required this.finalCents,
    required this.showOriginal,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final finalMoney = Money.fromCents(finalCents);
    final savedCents = plan.price.cents - finalCents;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          showOriginal ? '实付' : '合计',
          style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: Sp.sm),
        Text(
          finalMoney.isZero ? '免费' : finalMoney.display,
          style: textTheme.headlineSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (showOriginal && savedCents > 0) ...[
          const SizedBox(width: Sp.sm),
          Text(
            plan.price.display,
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const Spacer(),
          Text(
            '已优惠 ${Money.fromCents(savedCents).display}',
            style: textTheme.labelMedium?.copyWith(color: cs.primary),
          ),
        ],
      ],
    );
  }
}
