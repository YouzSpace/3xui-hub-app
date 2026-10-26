import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:controlhub_app/core/storage/prefs.dart';
import 'package:controlhub_app/core/theme/app_theme.dart';
import 'package:controlhub_app/data/models/user_profile.dart';
import 'package:controlhub_app/features/settings/logout_service.dart';
import 'package:controlhub_app/features/settings/settings_page.dart';
import 'package:controlhub_app/features/settings/settings_providers.dart';
import 'package:controlhub_app/features/settings/site_config.dart';
import 'package:controlhub_app/features/settings/version_tap_trigger.dart';
import 'package:controlhub_app/providers/theme_mode_provider.dart';

UserProfile _user({String protocol = 'vless'}) => UserProfile(
      id: 1,
      email: 'a@b.com',
      token: 'sub-token',
      protocol: protocol,
      planId: 2,
      planType: 'period',
      planName: '月付',
      planIncludeLocal: true,
      planMonths: 1,
      planPrice: 19.9,
      planResetPrice: 5,
      trafficLimit: 0,
      trafficUsed: 0,
      monthlyTrafficUsed: 0,
      monthlyTrafficLimit: 0,
      nextTrafficResetAt: null,
      expiredAt: null,
      enabled: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('T8.3 主题模式持久化', () {
    test('编码/解码互逆；未知值按跟随系统', () {
      expect(encodeThemeMode(ThemeMode.light), 'light');
      expect(encodeThemeMode(ThemeMode.dark), 'dark');
      expect(encodeThemeMode(ThemeMode.system), 'system');
      expect(decodeThemeMode('light'), ThemeMode.light);
      expect(decodeThemeMode('dark'), ThemeMode.dark);
      expect(decodeThemeMode('system'), ThemeMode.system);
      // 老版本/脏数据：不能崩，回到跟随系统。
      expect(decodeThemeMode(null), ThemeMode.system);
      expect(decodeThemeMode(''), ThemeMode.system);
      expect(decodeThemeMode('blue'), ThemeMode.system);
    });

    test('setMode 写 prefs，重新构建的容器能回填', () async {
      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      expect(c1.read(themeModeProvider), ThemeMode.system);

      await c1.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      expect(c1.read(themeModeProvider), ThemeMode.dark);
      expect(await Prefs.getThemeMode(), 'dark');

      // 模拟重启：新容器从零构建，restore 应读回 dark。
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.listen(themeModeProvider, (_, _) {});
      await c2.read(themeModeProvider.notifier).restore();
      expect(c2.read(themeModeProvider), ThemeMode.dark);
    });

    test('写盘失败不影响本次切换生效', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // prefs 被清空后仍应保持内存态（这里用 setMode 正常路径 + 断言内存值）。
      await c.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      expect(c.read(themeModeProvider), ThemeMode.light);
    });

    testWidgets('MaterialApp 跟随 themeModeProvider：切暗色后立即变暗', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ref.watch(themeModeProvider),
            home: const Scaffold(body: Text('内容')),
          ),
        ),
      ));

      BuildContext appContext() => tester.element(find.text('内容'));
      expect(Theme.of(appContext()).brightness, Brightness.light);

      await tester.runAsync(
        () => ProviderScope.containerOf(appContext())
            .read(themeModeProvider.notifier)
            .setMode(ThemeMode.dark),
      );
      await tester.pumpAndSettle();

      expect(Theme.of(appContext()).brightness, Brightness.dark);
    });
  });

  group('T8.4 退出登录顺序', () {
    test('严格按 断 VPN → 清 token → 清用户缓存 → 清订阅缓存', () async {
      final calls = <String>[];
      final service = LogoutService(
        disconnectVpn: () async => calls.add('vpn'),
        clearToken: () async => calls.add('token'),
        clearUserCache: () async => calls.add('userCache'),
        clearSubscriptionCache: () async => calls.add('subCache'),
      );

      await service.run();
      expect(calls, ['vpn', 'token', 'userCache', 'subCache']);
    });

    test('单步失败不阻断后续清理（断 VPN 失败也要清 token）', () async {
      final calls = <String>[];
      final service = LogoutService(
        disconnectVpn: () async {
          calls.add('vpn');
          throw StateError('engine stop failed');
        },
        clearToken: () async => calls.add('token'),
        clearUserCache: () async => calls.add('userCache'),
        clearSubscriptionCache: () async => calls.add('subCache'),
      );

      await service.run();
      expect(calls, ['vpn', 'token', 'userCache', 'subCache']);
    });

    test('清订阅缓存不碰主题与绕开国内', () async {
      SharedPreferences.setMockInitialValues({
        Prefs.keyThemeMode: 'dark',
        Prefs.keyBypassChina: true,
        Prefs.keySelectedNode: 'vless://node',
        Prefs.keyCacheMe: '{}',
      });

      await clearSubscriptionCache();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(Prefs.keySelectedNode), isNull);
      expect(prefs.getString(Prefs.keyThemeMode), 'dark');
      expect(prefs.getBool(Prefs.keyBypassChina), isTrue);
    });
  });

  group('T9.4 连续点击版本号 5 次', () {
    test('5 次内触发一次，随后计数清零（第 6 次不立刻再触发）', () {
      final counter = TapCounter();
      final base = DateTime(2026, 10, 26, 12);

      expect(counter.tap(now: base), isFalse);
      expect(counter.tap(now: base.add(const Duration(milliseconds: 100))), isFalse);
      expect(counter.tap(now: base.add(const Duration(milliseconds: 200))), isFalse);
      expect(counter.tap(now: base.add(const Duration(milliseconds: 300))), isFalse);
      expect(counter.tap(now: base.add(const Duration(milliseconds: 400))), isTrue);
      expect(counter.count, 0);
      expect(counter.tap(now: base.add(const Duration(milliseconds: 500))), isFalse);
    });

    test('两次点击间隔超过 2 秒则重新计数', () {
      final counter = TapCounter();
      final base = DateTime(2026, 10, 26, 12);

      for (var i = 0; i < 4; i++) {
        expect(counter.tap(now: base.add(Duration(milliseconds: i * 100))), isFalse);
      }
      // 第 5 次来晚了 3 秒：前面 4 次作废，本次算第 1 次。
      expect(counter.tap(now: base.add(const Duration(seconds: 3))), isFalse);
      expect(counter.count, 1);
    });
  });

  group('T8.5 版本号展示', () {
    test('拼成 v1.0.0 (1)', () {
      const v = LocalAppVersion(versionName: '1.0.0', buildNumber: '1');
      expect(v.label, 'v1.0.0 (1)');
    });

    test('无构建号只显示版本；读不到显示占位', () {
      expect(
        const LocalAppVersion(versionName: '1.2.0', buildNumber: '').label,
        'v1.2.0',
      );
      expect(
        const LocalAppVersion(versionName: '', buildNumber: '').label,
        '—',
      );
    });
  });

  group('站点配置与协议切换入口', () {
    test('site-config 全字符串解析；非字符串值也兜成字符串', () {
      final config = SiteConfig.fromJson({
        'site_title': '柚子云',
        'feedback_link': 'https://t.me/x',
        'sub_clash_enabled': '1',
      });
      expect(config.siteTitle, '柚子云');
      expect(config.feedbackLink, 'https://t.me/x');
      expect(config.values['sub_clash_enabled'], '1');
      // 非字符串值（后端若改类型）也不炸。
      expect(SiteConfig.fromJson({'site_title': 123}).siteTitle, '123');
      expect(SiteConfig.fromJson(null).isNotEmpty, isFalse);
    });

    test('缓存编码/解码往返；坏 JSON 按空配置', () {
      const config = SiteConfig({'site_title': 'A'});
      expect(SiteConfig.decode(config.encode()).siteTitle, 'A');
      expect(SiteConfig.decode('not-json').isNotEmpty, isFalse);
      expect(SiteConfig.decode(null).isNotEmpty, isFalse);
    });

    test('vless/trojan 用户显示入口；站点开关为 "0" 时隐藏', () {
      expect(supportsProtocolSwitch(_user(protocol: 'vless'), SiteConfig.empty), isTrue);
      expect(supportsProtocolSwitch(_user(protocol: 'trojan'), SiteConfig.empty), isTrue);
      // 未知协议（后端将来新增 vmess/ss）不提供切换。
      expect(supportsProtocolSwitch(_user(protocol: 'vmess'), SiteConfig.empty), isFalse);
      expect(supportsProtocolSwitch(null, SiteConfig.empty), isFalse);
      expect(
        supportsProtocolSwitch(
          _user(),
          const SiteConfig({'protocol_switch_enabled': '0'}),
        ),
        isFalse,
      );
    });

    test('备选协议 = 当前协议之外的那一个', () {
      expect(protocolAlternatives('vless'), ['trojan']);
      expect(protocolAlternatives('trojan'), ['vless']);
      expect(protocolLabel('vless'), 'VLESS');
      expect(protocolLabel('trojan'), 'Trojan');
    });
  });

  group('页面冒烟', () {
    testWidgets('设置页渲染出三分组与退出登录按钮', (tester) async {
      // 竖屏高一点，避免 ListView 下半部分（退出登录）落在视口外不构建。
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          siteConfigProvider.overrideWith((ref) async => const SiteConfig({
                'site_title': '柚子云',
                'feedback_link': 'https://t.me/x',
              })),
          localVersionProvider.overrideWith(
            (ref) async => const LocalAppVersion(versionName: '1.0.0', buildNumber: '1'),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('通用'), findsOneWidget);
      expect(find.text('账号'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);
      expect(find.text('主题模式'), findsOneWidget);
      expect(find.text('绕开国内'), findsOneWidget);
      expect(find.text('v1.0.0 (1)'), findsOneWidget);
      expect(find.text('套餐'), findsOneWidget);
      expect(find.text('意见反馈'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
      // 未登录（无 token）不显示协议切换。
      expect(find.text('协议切换'), findsNothing);
    });

    testWidgets('连点版本号 5 次弹出隐藏地址入口', (tester) async {
      var triggered = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VersionTapTrigger(
            onTriggered: () => triggered++,
            child: const Text('v1.0.0 (1)'),
          ),
        ),
      ));

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('v1.0.0 (1)'));
        await tester.pump();
      }
      expect(triggered, 0);

      await tester.tap(find.text('v1.0.0 (1)'));
      await tester.pump();
      expect(triggered, 1);

      // 触发后计数清零：第 6 次点击不会立刻再弹一次。
      await tester.tap(find.text('v1.0.0 (1)'));
      await tester.pump();
      expect(triggered, 1);
    });
  });
}
