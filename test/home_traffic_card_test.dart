import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/theme/app_theme.dart';
import 'package:controlhub_app/data/models/user_profile.dart';
import 'package:controlhub_app/widgets/traffic_card.dart';

const int _gb = 1024 * 1024 * 1024;

UserProfile _profile({
  int planId = 2,
  bool includeLocal = true,
  int used = 0,
  int limit = 0,
  DateTime? expiredAt,
  DateTime? resetAt,
}) =>
    UserProfile(
      id: 1,
      email: 'a@b.com',
      token: 'sub-token',
      protocol: 'vless',
      planId: planId,
      planType: 'period',
      planName: '月付',
      planIncludeLocal: includeLocal,
      planMonths: 1,
      planPrice: 19.9,
      planResetPrice: 5,
      trafficLimit: 0,
      trafficUsed: 0,
      monthlyTrafficUsed: used,
      monthlyTrafficLimit: limit,
      nextTrafficResetAt: resetAt,
      expiredAt: expiredAt ?? DateTime(2026, 11, 25),
      enabled: true,
    );

Future<void> _pump(
  WidgetTester tester,
  UserProfile profile, {
  VoidCallback? onBuy,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TrafficCard(profile: profile, onBuyPlan: onBuy ?? () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('T5.3 纯数据投影', () {
    test('未订阅优先于第三方套餐（后端无套餐也会下发 include_local=false）', () {
      final s = TrafficSummary.fromProfile(
        _profile(planId: 0, includeLocal: false),
      );
      expect(s.state, TrafficPlanState.noPlan);
    });

    test('limit=0 视为不限量：没有进度', () {
      final s = TrafficSummary.fromProfile(_profile(used: _gb, limit: 0));
      expect(s.isUnlimited, isTrue);
      expect(s.progress, isNull);
      expect(s.isNearLimit, isFalse);
    });

    test('已用/上限 计算剩余与 >90% 提醒；超出上限时进度封顶 1.0', () {
      final near = TrafficSummary.fromProfile(
        _profile(used: 95 * _gb, limit: 100 * _gb),
      );
      expect(near.progress, closeTo(0.95, 1e-9));
      expect(near.isNearLimit, isTrue);
      expect(near.remaining, 5 * _gb);

      final over = TrafficSummary.fromProfile(
        _profile(used: 120 * _gb, limit: 100 * _gb),
      );
      expect(over.progress, 1.0);
      expect(over.remaining, 0);
    });
  });

  group('T5.3 三种套餐状态 UI', () {
    testWidgets('纯第三方套餐：只显示到期日期，不显示流量', (tester) async {
      await _pump(
        tester,
        _profile(includeLocal: false, used: 3 * _gb, limit: 10 * _gb),
      );

      expect(find.byKey(const ValueKey('third-party')), findsOneWidget);
      expect(find.text('本套餐为第三方套餐，流量在对应平台查看'), findsOneWidget);
      expect(find.text('2026-11-25'), findsOneWidget);
      // 不该出现任何流量数字/进度条。
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('GB'), findsNothing);
    });

    testWidgets('未订阅：提示 + 去选购按钮可点', (tester) async {
      var taps = 0;
      await _pump(tester, _profile(planId: 0), onBuy: () => taps++);

      expect(find.byKey(const ValueKey('no-plan')), findsOneWidget);
      expect(find.text('去选购'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.tap(find.text('去选购'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('正常套餐：已用/剩余/进度 + 到期与距重置两列', (tester) async {
      await _pump(
        tester,
        _profile(
          used: 3 * _gb,
          limit: 10 * _gb,
          expiredAt: DateTime(2026, 11, 25),
          resetAt: DateTime.now().add(const Duration(days: 30)),
        ),
      );

      expect(find.text('本月已用'), findsOneWidget);
      expect(find.text('3.0 GB / 10.0 GB'), findsOneWidget); // 已用 / 上限 行
      expect(find.text('7.0 GB'), findsOneWidget); // 剩余
      expect(find.text('到期时间'), findsOneWidget);
      expect(find.text('距重置'), findsOneWidget);
      expect(find.text('30 天'), findsOneWidget);

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.3, 1e-6));
    });

    testWidgets('超过 90%：进度条转 error 色 + 「流量即将用完」', (tester) async {
      await _pump(tester, _profile(used: 95 * _gb, limit: 100 * _gb));

      expect(find.text('流量即将用完'), findsOneWidget);
      final cs = AppTheme.light().colorScheme;
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.color, cs.error);
    });

    testWidgets('limit=0：显示无限符号且隐藏进度条', (tester) async {
      await _pump(tester, _profile(used: 5 * _gb, limit: 0));

      expect(find.byKey(const ValueKey('unlimited')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('剩余'), findsNothing);
    });

    testWidgets('数字变化走 400ms 过渡（不是直接换字）', (tester) async {
      await _pump(tester, _profile(used: 1 * _gb, limit: 10 * _gb));
      expect(find.text('9.0 GB'), findsOneWidget);

      // 同一棵树里换数据：过渡期间新旧两个数字同时存在。
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TrafficCard(
                profile: _profile(used: 2 * _gb, limit: 10 * _gb),
                onBuyPlan: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('9.0 GB'), findsOneWidget);
      expect(find.text('8.0 GB'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('9.0 GB'), findsNothing);
      expect(find.text('8.0 GB'), findsOneWidget);
    });
  });
}
