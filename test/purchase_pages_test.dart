// M6 页面级测试（T6.3 / T6.6 / T6.4）：
// 覆盖套餐卡片两种布局、套餐页空态/列表、订单页空态、支付页两种失败前置校验。
// 真实 WebView 与真机支付不在单测范围（见任务书「真机支付联调后续统一做」）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/theme/app_theme.dart';
import 'package:controlhub_app/data/models/money.dart';
import 'package:controlhub_app/data/models/order.dart';
import 'package:controlhub_app/data/models/plan.dart';
import 'package:controlhub_app/data/models/pay_method.dart';
import 'package:controlhub_app/features/plans/buy_sheet.dart';
import 'package:controlhub_app/features/plans/order_history_page.dart';
import 'package:controlhub_app/features/plans/plan_card.dart';
import 'package:controlhub_app/features/plans/plans_page.dart';
import 'package:controlhub_app/features/plans/plans_provider.dart';
import 'package:controlhub_app/features/payment/payment_webview_page.dart';

Plan _plan({
  bool includeLocal = true,
  List<int> third = const [],
  String type = 'period',
  int months = 1,
  num price = 19.9,
}) =>
    Plan.fromJson({
      'id': 1,
      'name': '月付',
      'price': price,
      'type': type,
      'months': months,
      'monthly_traffic': 107374182400,
      'include_local': includeLocal,
      'third_party_sub_ids': third,
    });

Widget _wrap(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

void main() {
  testWidgets('PlanCard 渲染普通套餐：价格 + 流量', (tester) async {
    await tester.pumpWidget(_wrap(Scaffold(
      body: PlanCard(plan: _plan(), onBuy: () {}),
    )));
    // 卡片名 + 类型 chip 都是「月付」（月付套餐），两处出现是预期的。
    expect(find.text('月付'), findsNWidgets(2));
    expect(find.text('¥19.90'), findsOneWidget);
    expect(find.text('/月'), findsOneWidget);
    expect(find.text('100.0 GB'), findsOneWidget);
    expect(find.text('立即购买'), findsOneWidget);
  });

  testWidgets('PlanCard 纯第三方套餐：不显示流量，显示「流量随用随充」', (tester) async {
    await tester.pumpWidget(_wrap(Scaffold(
      body: PlanCard(
        plan: _plan(includeLocal: false, third: [5], price: 10),
        onBuy: () {},
      ),
    )));
    expect(find.text('流量随用随充'), findsOneWidget);
    expect(find.text('100.0 GB'), findsNothing);
  });

  testWidgets('PlansPage 空态', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(
      const PlansPage(),
      overrides: [plansProvider.overrideWith((ref) async => <Plan>[])],
    ));
    // 等 async override 落地（pumpAndSettle 不够：FutureProvider 有真实异步）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('暂无可用套餐'), findsOneWidget);
    expect(find.text('套餐'), findsOneWidget);
  });

  testWidgets('PlansPage 有数据：卡片列表 + 订单入口', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(
      const PlansPage(),
      overrides: [plansProvider.overrideWith((ref) async => [_plan()])],
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('立即购买'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
  });

  testWidgets('OrderHistoryPage 空态', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(
      const OrderHistoryPage(),
      overrides: [ordersProvider.overrideWith((ref) async => <Order>[])],
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('还没有订单记录'), findsOneWidget);
  });

  testWidgets('BuySheet 布局：支付方式单选 + 优惠码输入 + 去支付', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => BuySheet.show(context, _plan()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      overrides: [
        payMethodsProvider.overrideWith((ref) async => [
              const PayMethod(id: 1, name: '支付宝', bankCode: 'alipay'),
              const PayMethod(id: 2, name: '微信支付', bankCode: 'wechat'),
            ]),
      ],
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 标题、两种支付方式、优惠码入口、按钮都在。
    expect(find.text('购买 月付'), findsOneWidget);
    expect(find.byType(RadioListTile<int>), findsNWidgets(2));
    expect(find.text('支付宝'), findsOneWidget);
    expect(find.text('输入邀请码 / 兑换码'), findsOneWidget);
    expect(find.text('验证'), findsOneWidget);
    expect(find.text('去支付'), findsOneWidget);
    // 未验证优惠码时显示原价，不显示划线价。
    expect(find.text('¥19.90'), findsOneWidget);
  });

  testWidgets('PaymentWebviewPage 深链无参：提示参数缺失不崩', (tester) async {
    await tester.pumpWidget(_wrap(const PaymentWebviewPage()));
    await tester.pumpAndSettle();
    expect(find.text('支付'), findsOneWidget);
    expect(find.textContaining('订单参数缺失'), findsOneWidget);
  });

  testWidgets('PaymentWebviewPage 非法 payUrl：提示地址无效，不建 WebView', (tester) async {
    await tester.pumpWidget(_wrap(const PaymentWebviewPage(
      args: PaymentPageArgs(
        orderNo: 'N1',
        payUrl: 'javascript:alert(1)',
        amount: Money.zero,
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('支付地址无效'), findsOneWidget);
  });
}
