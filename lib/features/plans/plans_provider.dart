import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/order.dart';
import '../../data/models/pay_method.dart';
import '../../data/models/plan.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/plan_repository.dart';

/// M6 仓库 Provider：测试时可 override 注入 mock。
final planRepositoryProvider =
    Provider<PlanRepository>((ref) => PlanRepository());
final orderRepositoryProvider =
    Provider<OrderRepository>((ref) => OrderRepository());

/// 套餐列表（T6.3）：下拉刷新 / 重试都走 `ref.invalidate`。
final plansProvider = FutureProvider<List<Plan>>((ref) {
  return ref.read(planRepositoryProvider).fetchPlans();
});

/// 支付方式列表（T6.3 购买弹层用）：与套餐分离，弹层打开时才拉。
final payMethodsProvider = FutureProvider<List<PayMethod>>((ref) {
  return ref.read(orderRepositoryProvider).fetchMethods();
});

/// 订单记录（T6.6）：`refresh()` = invalidateSelf。
final ordersProvider = FutureProvider<List<Order>>((ref) {
  return ref.read(orderRepositoryProvider).fetchOrders();
});
