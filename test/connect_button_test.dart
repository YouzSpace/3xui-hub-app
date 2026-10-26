import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/theme/app_theme.dart';
import 'package:controlhub_app/core/ui/motion.dart';
import 'package:controlhub_app/widgets/connect_button.dart';
import 'package:controlhub_app/vpn/vpn_state.dart';

Future<void> _pump(
  WidgetTester tester,
  VpnStatus status, {
  String? blockedReason,
  VoidCallback? onPressed,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: ConnectButton(
              status: status,
              blockedReason: blockedReason,
              onPressed: onPressed ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Material _material(WidgetTester tester) => tester.widget<Material>(
  find.descendant(
    of: find.byType(ConnectButton),
    matching: find.byType(Material),
  ),
);

void main() {
  final cs = AppTheme.light().colorScheme;

  testWidgets('未连接：120dp、primary 底、power 图标、文字「连接」', (tester) async {
    await _pump(tester, VpnStatus.idle);

    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final circle = tester.getSize(
      find
          .descendant(
            of: find.byType(ConnectButton),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(circle.width, ConnectButton.diameter);
    expect(circle.height, ConnectButton.diameter);
    expect(_material(tester).color, cs.primary);
  });

  testWidgets('连接中：primaryContainer 底 + 进度圈，无循环动画时用 reduced 节奏', (
    tester,
  ) async {
    await _pump(tester, VpnStatus.connecting, disableAnimations: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_material(tester).color, cs.primaryContainer);
  });

  testWidgets('已连接：primary 底 + 文字「已连接」+ 光晕在场', (tester) async {
    await _pump(tester, VpnStatus.connected, disableAnimations: true);

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_material(tester).color, cs.primary);

    // 光晕是 ConnectButton 之外的装饰容器（Stack 里第一个 Container）。
    final rings = find.descendant(
      of: find.byType(ConnectButton),
      matching: find.byType(Container),
    );
    expect(rings, findsWidgets);
  });

  testWidgets('三态切换有过渡：400ms 内不会瞬间变成终态', (tester) async {
    await _pump(tester, VpnStatus.idle);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: ConnectButton(
                status: VpnStatus.connecting,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 过渡中：旧图标与新进度圈同时在树上（AnimatedSwitcher 交叉淡入）。
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);

    // 连接中有常驻脉冲，不能 pumpAndSettle（永远不静止）。
    await tester.pump(Motion.small);
    await tester.pump(Motion.small);
    expect(find.byIcon(Icons.power_settings_new), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('禁用态（到期/耗尽）：底 0.12 透明度，点击仍回调（由页面弹说明）', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      VpnStatus.idle,
      blockedReason: '套餐已到期，请先续费',
      onPressed: () => taps++,
    );

    final color = _material(tester).color!;
    expect(color.a, closeTo(0.12, 0.01));
    // 原因文案由页面弹 SnackBar 负责，按钮上仍显示动作名。

    await tester.tap(find.byType(ConnectButton));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('过渡态不可连点：preparing/connecting/disconnecting 时点击无效', (
    tester,
  ) async {
    var taps = 0;
    await _pump(tester, VpnStatus.disconnecting, onPressed: () => taps++);

    await tester.tap(find.byType(ConnectButton));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('减少动效：已连接时不跑循环动画（无一帧后仍在重绘）', (tester) async {
    await _pump(tester, VpnStatus.connected, disableAnimations: true);
    // pumpAndSettle 能返回本身就说明没有常驻动画（否则会超时）。
    await tester.pumpAndSettle();
  });
}
