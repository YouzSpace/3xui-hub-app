import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'apk_installer.dart';
import 'update_dialog.dart';
import 'version_reporter.dart';

/// 版本上报器（T9.6）：测试可 override 注入桩。
final versionReporterProvider = Provider<VersionReporter>((ref) {
  return VersionReporter();
});

/// 下载/安装器（T9.8）：弹窗内复用同一个实例，保证「已校验包」缓存有效。
final apkInstallerProvider = Provider<ApkInstaller>((ref) {
  return ApkInstaller(dio: buildDownloadDio());
});

/// 挂在首页的启动检查（T9.6：进首页后触发，不阻塞首屏）。
///
/// 直接包在首页外面即可：
/// ```dart
/// UpdateGate(child: HomePage())
/// ```
/// 守卫自身的 build 只返回 [child]，网络请求在首个帧之后才发，
/// 所以首屏渲染完全不受影响；失败/未配置/无更新时什么都不显示。
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  @override
  void initState() {
    super.initState();
    // 等首帧画完再查更新：规格要求「进首页后触发，不阻塞启动首屏」。
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (!mounted) return;
    final VersionDecision? decision;
    try {
      decision = await ref.read(versionReporterProvider).report();
    } catch (e) {
      // report 内部已吞掉所有异常，这里只是双保险：检查更新绝不影响使用。
      if (kDebugMode) debugPrint('update check failed: $e');
      return;
    }
    if (decision == null || !mounted) return;
    showDecisionDialog(decision);
  }

  /// 弹更新框。
  ///
  /// 不 await：强制更新弹窗在用户装完之前一直开着，await 只会挂住
  /// 这个回调（无副作用，但也无收益）。失败/稍后都在弹窗内部收敛。
  void showDecisionDialog(VersionDecision decision) {
    showUpdateDialog(
      context,
      decision,
      installer: ref.read(apkInstallerProvider),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 手动检查更新（设置页「检查更新」用，M8 接入）。
///
/// 绕过节流但只拿决策、不弹窗 —— 由调用方决定「已是最新」还是弹更新框。
/// 返回 null = 无更新/失败（静默）。
Future<VersionDecision?> checkUpdateManually(WidgetRef ref) =>
    ref.read(versionReporterProvider).report(force: true);

/// 任何页面都可直接调用：查一次（守 24h 节流）并弹窗，失败静默。
Future<void> runStartupUpdateCheck(BuildContext context, WidgetRef ref) async {
  final decision = await ref.read(versionReporterProvider).report();
  if (decision == null || !context.mounted) return;
  await showUpdateDialog(
    context,
    decision,
    installer: ref.read(apkInstallerProvider),
  );
}
