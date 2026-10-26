import 'package:go_router/go_router.dart';

import '../../core/router/transitions.dart';
import '../payment/payment_webview_page.dart';
import 'order_history_page.dart';
import 'plans_page.dart';

/// M6 路由（T6.3–T6.6）。
///
/// 边界铁律：M6 只导出这个 `List<GoRoute>`，**绝不改** `lib/core/router/app_router.dart`
/// —— 并行期间其他 agent 也在改它，最后由汇总方把 [plansRoutes] 拼进总表。
///
/// 路径约定（与 app_router.dart 现有占位页一致，汇总时直接替换即可）：
/// - `/plans`     套餐列表（Tab 分支）
/// - `/payment`   支付 WebView（二级页，右滑入）
/// - `/orders`    订单记录（二级页，右滑入）
abstract class PlansRoutes {
  static const plans = '/plans';
  static const payment = '/payment';
  static const orders = '/orders';
}

/// 支付页入参（`context.push(PlansRoutes.payment, extra: PaymentArgs(...))`）。
///
/// 用 extra 传对象而不是 query：payUrl 带签名参数，塞进 URL 会被日志/历史记录留痕。
/// 直接深链进入 `/payment` 而没有 extra 时，页面显示「订单参数缺失」并可返回。
typedef PaymentArgs = PaymentPageArgs;

/// M6 的所有路由，交给汇总方拼进 `app_router.dart`。
final List<GoRoute> plansRoutes = [
  GoRoute(
    path: PlansRoutes.plans,
    pageBuilder: (context, state) =>
        AppTransitions.fadeLift(state: state, child: const PlansPage()),
  ),
  GoRoute(
    path: PlansRoutes.payment,
    pageBuilder: (context, state) => AppTransitions.slideFromRight(
      state: state,
      child: PaymentWebviewPage(args: state.extra as PaymentArgs?),
    ),
  ),
  GoRoute(
    path: PlansRoutes.orders,
    pageBuilder: (context, state) =>
        AppTransitions.slideFromRight(state: state, child: const OrderHistoryPage()),
  ),
];
