import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:controlhub_app/features/update/apk_installer.dart';
import 'package:controlhub_app/features/update/update_dialog.dart';
import 'package:controlhub_app/features/update/update_providers.dart';
import 'package:controlhub_app/features/update/version_reporter.dart';

/// 记录请求参数、按用例返回预设 data 的桩（T9.6 单测）。
class _StubVersionApi implements VersionApi {
  _StubVersionApi(this._respond);

  final Future<Map<String, dynamic>?> Function() _respond;
  final List<Map<String, String>> calls = [];

  @override
  Future<Map<String, dynamic>?> fetch({
    required String versionCode,
    required String versionName,
    required String packageId,
  }) {
    calls.add({
      'version_code': versionCode,
      'version_name': versionName,
      'package_id': packageId,
    });
    return _respond();
  }
}

/// 固定本机版本（不读平台通道）。
LocalVersion _local([String code = '13']) => LocalVersion(
      versionName: '1.3.0',
      buildNumber: code,
      packageName: 'com.controlhub.controlhub_app',
    );

/// 后端 data 的典型 shape（Go 端数字字段是 number，字符串字段可能是空串/null）。
Map<String, dynamic> _data({
  String action = 'optional',
  Object? latestName = '1.5.0',
  Object? latestCode = 15,
  Object? url = 'https://dl.example.com/app-1.5.0.apk',
  Object? size = 38200000,
  Object? sha = 'a1b2c3',
  Object? notes = '修复连接超时\n优化测速',
  Object? minSupported = 10,
}) =>
    {
      'action': action,
      'latest_version_name': latestName,
      'latest_version_code': latestCode,
      'download_url': url,
      'size': size,
      'sha256': sha,
      'notes': notes,
      'min_supported_code': minSupported,
    };

VersionReporter _reporter(
  _StubVersionApi api, {
  Duration timeout = const Duration(seconds: 5),
}) =>
    VersionReporter(
      api: api,
      localVersion: () async => _local(),
      timeout: timeout,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 每个用例隔离 prefs（last_check_at 在 prefs 里，串了会互相跳过）。
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------- T9.6
  group('T9.6 版本上报：五种返回', () {
    test('① action=none → 返回 null 并静默', () async {
      final api = _StubVersionApi(() async => _data(action: 'none'));
      expect(await _reporter(api).report(), isNull);
      // 上报本身仍发生了（后端要统计版本分布）。
      expect(api.calls.single['version_code'], '13');
    });

    test('② action=optional → 返回完整决策', () async {
      final api = _StubVersionApi(() async => _data());
      final d = await _reporter(api).report();
      expect(d, isNotNull);
      expect(d!.isOptional, isTrue);
      expect(d.latestName, '1.5.0');
      expect(d.latestCode, 15);
      expect(d.downloadUrl, 'https://dl.example.com/app-1.5.0.apk');
      expect(d.size, 38200000);
      expect(d.sha256, 'a1b2c3');
      expect(d.minSupportedCode, 10);
      // 更新说明落进决策时已按 \n 归一（\r\n 也不会留 \r）。
      expect(d.notes, '修复连接超时\n优化测速');
    });

    test('③ action=force → 返回 force 决策', () async {
      final api = _StubVersionApi(() async => _data(action: 'force'));
      final d = await _reporter(api).report();
      expect(d, isNotNull);
      expect(d!.isForce, isTrue);
      expect(d.isOptional, isFalse);
    });

    test('④ 超时 → 返回 null，不阻塞调用方', () async {
      final api = _StubVersionApi(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return _data();
      });
      final d = await _reporter(
        api,
        timeout: const Duration(milliseconds: 50),
      ).report();
      expect(d, isNull);
    });

    test('⑤ data 为 null（站点未配置）→ 返回 null', () async {
      final api = _StubVersionApi(() async => null);
      expect(await _reporter(api).report(), isNull);
    });

    test('附加：网络异常 → 返回 null（检查更新绝不影响使用）', () async {
      final api = _StubVersionApi(() async => throw const SocketException('x'));
      expect(await _reporter(api).report(), isNull);
    });

    test('附加：optional 但没给 download_url → 按静默处理', () async {
      final api = _StubVersionApi(() async => _data(url: ''));
      expect(await _reporter(api).report(), isNull);
    });

    test('上报参数：version_code/version_name/package_id 都来自本机', () async {
      final api = _StubVersionApi(() async => _data(action: 'none'));
      await _reporter(api).report();
      expect(api.calls.single, {
        'version_code': '13',
        'version_name': '1.3.0',
        'package_id': 'com.controlhub.controlhub_app',
      });
    });

    test('版本号非数字（构建号异常）→ version_code 按 0 上报', () async {
      final api = _StubVersionApi(() async => _data(action: 'none'));
      final reporter = VersionReporter(
        api: api,
        localVersion: () async => const LocalVersion(
          versionName: 'dev',
          buildNumber: 'dev',
          packageName: 'pkg',
        ),
      );
      await reporter.report();
      expect(api.calls.single['version_code'], '0');
    });

    test('VersionDecision.fromJson 吃字符串数字（契约文字写法）', () {
      final d = VersionDecision.fromJson({
        'action': 'optional',
        'latest_version_code': '15',
        'size': '38200000',
        'min_supported_code': '10',
        'latest_version_name': '1.5.0',
        'download_url': 'https://x/y.apk',
      });
      expect(d!.latestCode, 15);
      expect(d.size, 38200000);
      expect(d.minSupportedCode, 10);
    });

    test('VersionDecision.fromJson 未知 action / 非 Map → null', () {
      expect(VersionDecision.fromJson({'action': 'weird'}), isNull);
      expect(VersionDecision.fromJson({'no_action': 1}), isNull);
      expect(VersionDecision.fromJson('oops'), isNull);
      expect(VersionDecision.fromJson(null), isNull);
    });

    test('24 小时内不重复请求（last_check_at 节流）', () async {
      final api = _StubVersionApi(() async => _data(action: 'none'));
      final reporter = _reporter(api);
      await reporter.report();
      expect(api.calls, hasLength(1));
      // 第二次：节流命中，不再发请求。
      expect(await reporter.report(), isNull);
      expect(api.calls, hasLength(1));
      // force: true 绕过节流（设置页「检查更新」）。
      await reporter.report(force: true);
      expect(api.calls, hasLength(2));
    });

    test('断网失败不写 last_check_at：下次启动还会重试', () async {
      var fail = true;
      final api = _StubVersionApi(() async {
        if (fail) throw const SocketException('offline');
        return _data();
      });
      final reporter = _reporter(api);
      expect(await reporter.report(), isNull); // 失败
      fail = false;
      expect(await reporter.report(), isNotNull); // 未节流 → 立刻重试成功
      expect(api.calls, hasLength(2));
    });
  });

  // ---------------------------------------------------------------- T9.7
  group('T9.7 升级弹窗：两种形态', () {
    test('optional：遮罩可关、返回键可关、有[稍后][立即更新]', () {
      final c = UpdateDialogConfig.from(
        const VersionDecision(action: 'optional'),
      );
      expect(c.force, isFalse);
      expect(c.barrierDismissible, isTrue);
      expect(c.backButtonCloses, isTrue);
      expect(c.canDefer, isTrue);
      expect(c.actions, ['稍后', '立即更新']);
      expect(c.title, '发现新版本');
    });

    test('force：遮罩不可关、返回键不可关、只有[立即更新]', () {
      final c = UpdateDialogConfig.from(
        const VersionDecision(action: 'force'),
      );
      expect(c.force, isTrue);
      expect(c.barrierDismissible, isFalse);
      expect(c.backButtonCloses, isFalse);
      expect(c.canDefer, isFalse);
      expect(c.actions, ['立即更新']);
      expect(c.title, '需要更新后才能继续使用');
    });

    test('更新说明按 \\n 分行，空行与首尾空白丢掉', () {
      final lines = UpdateDialog.splitNotes('修复 A\n\n  优化 B  \n\n');
      expect(lines, ['修复 A', '优化 B']);
      expect(UpdateDialog.splitNotes(null), isEmpty);
      expect(UpdateDialog.splitNotes('   '), isEmpty);
    });

    test('版本名标签：有名字显示「新版本 x」，没有就隐藏', () {
      expect(
        UpdateDialog.versionLabel(
          const VersionDecision(action: 'optional', latestName: '1.5.0'),
        ),
        '新版本 1.5.0',
      );
      expect(
        UpdateDialog.versionLabel(const VersionDecision(action: 'force')),
        isNull,
      );
    });

    testWidgets('optional 弹窗：三个信息块都在，点稍后返回 later', (tester) async {
      UpdateChoice? choice;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                choice = await showDialog<UpdateChoice>(
                  context: context,
                  builder: (_) => UpdateDialog(
                    decision: const VersionDecision(
                      action: 'optional',
                      latestName: '1.5.0',
                      downloadUrl: 'https://x/y.apk',
                      size: 38200000,
                      notes: '修复连接超时\n优化测速',
                    ),
                    onLater: () => Navigator.of(context).pop(UpdateChoice.later),
                    onInstall: () =>
                        Navigator.of(context).pop(UpdateChoice.install),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('新版本 1.5.0'), findsOneWidget);
      expect(find.text('修复连接超时'), findsOneWidget);
      expect(find.text('优化测速'), findsOneWidget);
      // 38200000 bytes = 36.4 MB（1024 进制，formatters.formatBytes）。
      expect(find.text('安装包 36.4 MB'), findsOneWidget);
      expect(find.text('稍后'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);

      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(choice, UpdateChoice.later);
    });

    testWidgets('force 弹窗：点遮罩关不掉、返回键关不掉、没有[稍后]',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => UpdateDialog(
                  decision: const VersionDecision(
                    action: 'force',
                    latestName: '2.0.0',
                    downloadUrl: 'https://x/y.apk',
                  ),
                  onInstall: () {},
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('需要更新后才能继续使用'), findsOneWidget);
      expect(find.text('稍后'), findsNothing);

      // 点遮罩（左上角远离对话框）。
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('需要更新后才能继续使用'), findsOneWidget,
          reason: 'force 弹窗点遮罩不应关闭');

      // 返回键（PopScope canPop:false）。
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(find.text('需要更新后才能继续使用'), findsOneWidget,
          reason: 'force 弹窗返回键不应关闭');
    });

    testWidgets('optional 弹窗：点遮罩可以关闭', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const UpdateDialog(
                  decision: VersionDecision(action: 'optional'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsOneWidget);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsNothing);
    });

    testWidgets('下载中：显示百分比与已下载/总量，不给按钮', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UpdateDialog(
            decision: const VersionDecision(
              action: 'force',
              latestName: '2.0.0',
              size: 1000,
            ),
            phase: UpdateDialogPhase.downloading,
            progress: const DownloadProgress(received: 500, total: 1000),
          ),
        ),
      ));
      expect(find.text('正在下载…'), findsOneWidget);
      expect(find.text('50%  500 B / 1000 B'), findsOneWidget);
      expect(find.text('立即更新'), findsNothing);
    });

    testWidgets('失败态：错误文案 + [重试]，不显示[立即更新]', (tester) async {
      var retried = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UpdateDialog(
            decision: const VersionDecision(action: 'optional'),
            phase: UpdateDialogPhase.failed,
            errorMessage: '安装包校验失败，请重试',
            onRetry: () => retried++,
            onLater: () {},
          ),
        ),
      ));
      expect(find.text('安装包校验失败，请重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, 1);
    });
  });

  // ------------------------------------------------- 启动触发（不阻塞首屏）
  group('启动检查：进首页后触发，不阻塞首屏', () {
    testWidgets('首帧先渲染内容，之后才发起上报', (tester) async {
      final events = <String>[];
      final api = _StubVersionApi(() async {
        events.add('fetch');
        return _data(action: 'none');
      });
      var builtHome = 0;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          versionReporterProvider.overrideWithValue(
            VersionReporter(api: api, localVersion: () async => _local()),
          ),
          apkInstallerProvider.overrideWithValue(
            ApkInstaller(
              dio: _dioWith(const []),
              storage: _MemStorage(),
              channel: _StubChannel(),
            ),
          ),
        ],
        child: MaterialApp(
          home: UpdateGate(
            child: Builder(builder: (context) {
              builtHome++;
              events.add('build');
              return const Scaffold(body: Text('首页内容'));
            }),
          ),
        ),
      ));

      // 第一帧：首页内容已经画出来（postFrame 回调在此之后才跑）。
      await tester.pump();
      expect(find.text('首页内容'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(api.calls, hasLength(1));
      // 关键顺序：先 build 首页，再发上报 —— 上报不阻塞首屏。
      expect(events, ['build', 'fetch']);
      expect(builtHome, 1, reason: '检查更新不应重建首页');
      // action=none → 不弹任何东西。
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('发现新版本'), findsNothing);
    });

    testWidgets('optional 决策 → 首屏出来后自动弹可选更新框', (tester) async {
      final api = _StubVersionApi(() async => _data(action: 'optional'));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          versionReporterProvider.overrideWithValue(
            VersionReporter(api: api, localVersion: () async => _local()),
          ),
          apkInstallerProvider.overrideWithValue(
            ApkInstaller(
              dio: _dioWith(const []),
              storage: _MemStorage(),
              channel: _StubChannel(),
            ),
          ),
        ],
        child: const MaterialApp(
          home: UpdateGate(child: Scaffold(body: Text('首页内容'))),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('首页内容'), findsOneWidget);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('稍后'), findsOneWidget);
    });

    testWidgets('force 决策 → 自动弹强制更新框，返回键关不掉', (tester) async {
      final api = _StubVersionApi(() async => _data(action: 'force'));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          versionReporterProvider.overrideWithValue(
            VersionReporter(api: api, localVersion: () async => _local()),
          ),
          apkInstallerProvider.overrideWithValue(
            ApkInstaller(
              dio: _dioWith(const []),
              storage: _MemStorage(),
              channel: _StubChannel(),
            ),
          ),
        ],
        child: const MaterialApp(
          home: UpdateGate(child: Scaffold(body: Text('首页内容'))),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('需要更新后才能继续使用'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('需要更新后才能继续使用'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------- T9.8
  group('T9.8 下载与安装：SHA256 校验', () {
    test('normalizeSha：大小写 / sha256: 前缀 / 空白', () {
      expect(ApkInstaller.normalizeSha(' ABCDEF '), 'abcdef');
      expect(ApkInstaller.normalizeSha('sha256:ABC'), 'abc');
      expect(ApkInstaller.normalizeSha(''), isNull);
      expect(ApkInstaller.normalizeSha(null), isNull);
    });

    test('SHA256 不一致 → 删文件 + 提示重试，不拉起安装器', () async {
      final storage = _MemStorage();
      final channel = _StubChannel();
      final installer = ApkInstaller(
        dio: _dioWith(utf8.encode('payload')),
        storage: storage,
        channel: channel,
      );

      final r = await installer.downloadAndInstall(
        url: 'https://x/y.apk',
        expectedSha256: 'deadbeef',
      );

      expect(r.status, InstallStatus.failed);
      expect(r.message, '安装包校验失败，请重试');
      expect(storage.deleted, isTrue, reason: '不匹配必须删临时文件');
      expect(channel.installs, isEmpty, reason: '校验不过不能拉起安装器');
    });

    test('SHA256 一致 → 拉起安装器，文件保留', () async {
      final payload = utf8.encode('payload');
      final expected = sha256.convert(payload).toString();
      final storage = _MemStorage();
      final channel = _StubChannel();
      final installer = ApkInstaller(
        dio: _dioWith(payload),
        storage: storage,
        channel: channel,
      );

      final r = await installer.downloadAndInstall(
        url: 'https://x/y.apk',
        expectedSha256: expected.toUpperCase(),
      );

      expect(r.ok, isTrue);
      expect(channel.installs, hasLength(1));
      expect(storage.deleted, isFalse, reason: '安装器进程还要读这个文件');
    });

    test('权限被拒 → permissionDenied，保留已校验包供授权后重试', () async {
      final payload = utf8.encode('payload');
      final storage = _MemStorage();
      final channel = _StubChannel(allowed: false);
      final installer = ApkInstaller(
        dio: _dioWith(payload),
        storage: storage,
        channel: channel,
      );

      final r = await installer.downloadAndInstall(
        url: 'https://x/y.apk',
        expectedSha256: sha256.convert(payload).toString(),
      );
      expect(r.status, InstallStatus.permissionDenied);
      expect(r.message, contains('未知来源'));

      // 用户去设置授权后点重试：不再下载（用已校验的包）。
      channel.allowed = true;
      final again = await installer.downloadAndInstall(
        url: 'https://x/y.apk',
        expectedSha256: sha256.convert(payload).toString(),
      );
      expect(again.ok, isTrue);
      expect(channel.installs, hasLength(1));
    });

    test('下载失败（非 2xx）→ failed + 文案，清理临时文件', () async {
      final storage = _MemStorage();
      final installer = ApkInstaller(
        dio: _dioWith(const [], statusCode: 404),
        storage: storage,
        channel: _StubChannel(),
      );
      final r = await installer.downloadAndInstall(
        url: 'https://x/y.apk',
        expectedSha256: null,
      );
      expect(r.status, InstallStatus.failed);
      expect(r.message, isNotNull);
      expect(storage.deleted, isTrue);
    });

    test('服务端未给 Content-Length → 进度未知，仍能装成功', () async {
      final payload = utf8.encode('payload');
      final storage = _MemStorage();
      final channel = _StubChannel();
      final installer = ApkInstaller(
        dio: _dioWith(payload, declareLength: false),
        storage: storage,
        channel: channel,
      );
      final seen = <DownloadProgress>[];
      final r = await installer.downloadAndInstall(
        url: 'https://x/y.apk',
        expectedSha256: null,
        onProgress: seen.add,
      );
      expect(r.ok, isTrue);
      expect(seen.last.known, isFalse);
      expect(seen.last.received, payload.length);
    });

    test('下载不完整（Content-Length 大于实际字节）→ failed + 清理', () async {
      final storage = _MemStorage();
      final installer = ApkInstaller(
        // 声称 10 字节，实际只给 3 字节。
        dio: _dioWith(const [1, 2, 3], declaredLength: 10),
        storage: storage,
        channel: _StubChannel(),
      );
      final r = await installer.downloadAndInstall(
        url: 'https://x/y.apk',
        expectedSha256: null,
      );
      expect(r.status, InstallStatus.failed);
      expect(r.message, contains('下载不完整'));
      expect(storage.deleted, isTrue);
    });

    test('CancelToken 取消 → cancelled（可选更新要能回到提示态）', () async {
      final storage = _MemStorage();
      final token = CancelToken();
      token.cancel();
      final installer = ApkInstaller(
        dio: _dioWith(utf8.encode('payload')),
        storage: storage,
        channel: _StubChannel(),
      );
      final r = await installer.downloadAndInstall(
        url: 'https://x/y.apk',
        expectedSha256: null,
        cancelToken: token,
      );
      expect(r.status, InstallStatus.cancelled);
      expect(storage.deleted, isTrue, reason: '取消也要清理临时文件');
    });

    test('校验阶段回调：下载完成后、拉起安装器之前触发', () async {
      final payload = utf8.encode('payload');
      final channel = _StubChannel();
      final installer = ApkInstaller(
        dio: _dioWith(payload),
        storage: _MemStorage(),
        channel: channel,
      );
      final events = <String>[];
      final r = await installer.downloadAndInstall(
        url: 'https://x/y.apk',
        expectedSha256: sha256.convert(payload).toString(),
        onVerifying: () => events.add('verifying'),
        onProgress: (_) => events.add('progress'),
      );
      expect(r.ok, isTrue);
      expect(events.contains('verifying'), isTrue);
      expect(events.last, 'verifying', reason: '校验是最后一步，之后才装');
      expect(channel.installs, hasLength(1));
    });

    test('下载进度回调按 chunk 节流，且最后一次一定回调总量', () async {
      final payload = Uint8List(50 * 1024); // 50KB
      final storage = _MemStorage();
      final seen = <DownloadProgress>[];
      final installer = ApkInstaller(
        dio: _dioWith(payload),
        storage: storage,
        channel: _StubChannel(),
        chunkBytes: 1024, // 每 1KB 回调一次
      );
      final r = await installer.downloadAndInstall(
        url: 'https://x/y.apk',
        expectedSha256: null,
        onProgress: seen.add,
      );
      expect(r.ok, isTrue);
      expect(seen, isNotEmpty);
      expect(seen.last.total, payload.length);
      expect(seen.last.fraction, 1.0);
      expect(seen.last.percent, 100);
    });

    test('进度回调：百分比与总量按 Content-Length 计算', () {
      const p = DownloadProgress(received: 512, total: 1024);
      expect(p.fraction, 0.5);
      expect(p.percent, 50);
      expect(p.known, isTrue);
      // 服务端没给总长（0）→ 不确定进度，不能算出假百分比。
      const unknown = DownloadProgress(received: 512, total: 0);
      expect(unknown.known, isFalse);
      expect(unknown.percent, 0);
    });
  });
}

// ----------------------------------------------------------------- 测试桩

/// 内存文件系统：下载内容存进 [buffer]，记录是否被删。
class _MemStorage implements ApkStorage {
  final BytesBuilder buffer = BytesBuilder();
  bool deleted = false;

  @override
  Future<File> targetFile(String name) async => File('/tmp/$name-1.apk');

  @override
  Future<IOSink> openWrite(File file) async => _MemSink(buffer);

  @override
  Future<String> sha256Of(File file) async => sha256.convert(buffer.toBytes()).toString();

  @override
  Future<bool> exists(File file) async => !deleted;

  @override
  Future<void> delete(File file) async => deleted = true;
}

/// 把字节写进内存 buffer 的 sink。
class _MemSink implements IOSink {
  _MemSink(this._buffer);

  final BytesBuilder _buffer;
  final Completer<void> _done = Completer<void>();

  @override
  void add(List<int> data) => _buffer.add(data);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding value) {}

  @override
  Future<void> get done => _done.future;

  @override
  void write(Object? object) => add(utf8.encode('$object'));

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');
}

/// 走 dio 的真实下载管线：用自定义 adapter 喂固定字节（含 Content-Length）。
class _MemAdapter implements HttpClientAdapter {
  _MemAdapter(
    this.bytes, {
    this.statusCode = 200,
    this.declareLength = true,
    int? declaredLength,
  }) : declaredLength = declaredLength ?? bytes.length;

  final List<int> bytes;
  final int statusCode;

  /// false 模拟服务端不给 Content-Length（进度只能显示已下载量）。
  final bool declareLength;

  /// 声称的总长度；大于实际字节数可模拟「下载不完整」。
  final int declaredLength;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromBytes(
        bytes,
        statusCode,
        headers: declareLength
            ? {
                Headers.contentLengthHeader: ['$declaredLength'],
              }
            : const {},
      );

  @override
  void close({bool force = false}) {}
}

/// 构造一个走 [_MemAdapter] 的 Dio（真实拦截器 / validateStatus 都会执行）。
Dio _dioWith(
  List<int> bytes, {
  int statusCode = 200,
  bool declareLength = true,
  int? declaredLength,
}) =>
    Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ))
      ..httpClientAdapter = _MemAdapter(
        bytes,
        statusCode: statusCode,
        declareLength: declareLength,
        declaredLength: declaredLength,
      );

class _StubChannel implements ApkInstallChannel {
  _StubChannel({this.allowed = true});

  /// 是否有「安装未知来源」授权（测试中途可改，模拟用户去设置里打开）。
  bool allowed;
  final List<String> installs = [];

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> openInstallSettings() async {}

  @override
  Future<String?> install(String filePath) async {
    installs.add(filePath);
    return null;
  }
}
