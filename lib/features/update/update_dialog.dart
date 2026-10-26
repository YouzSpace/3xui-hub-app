import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/motion.dart';
import '../../core/utils/formatters.dart';
import 'apk_installer.dart';
import 'version_reporter.dart';

/// 更新弹窗（T9.7 / ui-glass-motion §3.2 #16）。
///
/// - `optional`：版本名 + 更新说明（按 `\n` 分行）+ 安装包大小 + [稍后][立即更新]
/// - `force`：只有 [立即更新]，`barrierDismissible: false`，返回键无效
///
/// 弹窗只负责「要不要更新」；点 [立即更新] 后同一个弹窗内切到下载/校验态，
/// 避免强制更新时把用户丢到一个可以退出的页面上。
enum UpdateChoice { later, install }

/// 弹窗阶段：同一个弹窗内演进，不额外起页面。
enum UpdateDialogPhase { prompt, downloading, verifying, failed }

/// 弹窗的可关闭性/按钮组合（纯逻辑，单测直接验证 T9.7）。
class UpdateDialogConfig {
  const UpdateDialogConfig({required this.force});

  factory UpdateDialogConfig.from(VersionDecision decision) =>
      UpdateDialogConfig(force: decision.isForce);

  /// 强制更新：不可关闭、只给一个按钮。
  final bool force;

  /// 点外部遮罩能否关闭（强制更新时 false）。
  bool get barrierDismissible => !force;

  /// Android 返回键能否关闭（强制更新时 false，见 [UpdateDialog] 的 PopScope）。
  bool get backButtonCloses => !force;

  /// 有「稍后」按钮 = 允许推迟。
  bool get canDefer => !force;

  /// 按钮文案，顺序即展示顺序。
  List<String> get actions =>
      force ? const ['立即更新'] : const ['稍后', '立即更新'];

  String get title => force ? '需要更新后才能继续使用' : '发现新版本';
}

/// 打开更新弹窗，走完「提示 → 下载 → 校验 → 拉起安装器」。
///
/// 返回最终结果：`null` = 用户选了稍后（或强制更新窗口被系统销毁）。
Future<InstallResult?> showUpdateDialog(
  BuildContext context,
  VersionDecision decision, {
  ApkInstaller? installer,
}) {
  final config = UpdateDialogConfig.from(decision);
  return showDialog<InstallResult?>(
    context: context,
    barrierDismissible: config.barrierDismissible,
    builder: (context) => UpdateFlowDialog(
      decision: decision,
      installer: installer ?? ApkInstaller(dio: buildDownloadDio()),
    ),
  );
}

/// 弹窗展示层：纯展示 + 回调，便于 widget 测试覆盖两种弹窗形态。
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.decision,
    this.phase = UpdateDialogPhase.prompt,
    this.progress,
    this.errorMessage,
    this.onInstall,
    this.onLater,
    this.onRetry,
    this.onOpenSettings,
  });

  final VersionDecision decision;
  final UpdateDialogPhase phase;
  final DownloadProgress? progress;
  final String? errorMessage;

  final VoidCallback? onInstall;
  final VoidCallback? onLater;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final config = UpdateDialogConfig.from(decision);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final notes = splitNotes(decision.notes);

    return PopScope(
      // 强制更新：返回键无效（规格硬要求）。
      canPop: config.backButtonCloses,
      child: Dialog(
        insetPadding: const EdgeInsets.all(Sp.base),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(Sp.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_outlined,
                        size: 32, color: cs.primary),
                    const SizedBox(width: Sp.md),
                    Expanded(
                      child: Text(config.title, style: textTheme.titleLarge),
                    ),
                  ],
                ),
                if (versionLabel(decision) case final label?) ...[
                  const SizedBox(height: Sp.sm),
                  Text(
                    label,
                    style:
                        textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: Sp.base),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in notes)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Sp.xs),
                              child: Text(line, style: textTheme.bodyMedium),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_hasSize(decision)) ...[
                  const SizedBox(height: Sp.md),
                  Row(
                    children: [
                      Icon(Icons.sd_storage_outlined,
                          size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: Sp.sm),
                      Text(
                        '安装包 ${formatBytes(decision.size!)}',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Sp.lg),
                _buildFooter(context, config),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, UpdateDialogConfig config) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    switch (phase) {
      case UpdateDialogPhase.prompt:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (config.canDefer) ...[
              TextButton(
                onPressed: onLater,
                child: const Text('稍后'),
              ),
              const SizedBox(width: Sp.sm),
            ],
            FilledButton(
              onPressed: onInstall,
              child: const Text('立即更新'),
            ),
          ],
        );

      case UpdateDialogPhase.downloading:
      case UpdateDialogPhase.verifying:
        final p = progress;
        final label = phase == UpdateDialogPhase.verifying
            ? '正在校验安装包…'
            : '正在下载…';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: textTheme.bodyMedium),
                if (phase == UpdateDialogPhase.downloading && p != null)
                  Text(
                    p.known
                        ? '${p.percent}%  ${formatBytes(p.received)} / ${formatBytes(p.total)}'
                        : formatBytes(p.received),
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Sp.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(Sp.xs),
              child: LinearProgressIndicator(
                // 服务端没给总长时不显示确定进度（避免假进度条）。
                value: phase == UpdateDialogPhase.downloading && p != null
                    ? (p.known ? p.fraction : null)
                    : null,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: Sp.lg),
            // 下载中不给任何按钮：避免重复触发与「看似可以退出」的误解。
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: null,
                child: Text(config.force ? '更新中，请稍候' : '下载中'),
              ),
            ),
          ],
        );

      case UpdateDialogPhase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 20, color: cs.error),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    errorMessage ?? '下载失败，请重试',
                    style: textTheme.bodyMedium?.copyWith(color: cs.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Sp.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onOpenSettings != null) ...[
                  TextButton(
                    onPressed: onOpenSettings,
                    child: const Text('去设置'),
                  ),
                  const SizedBox(width: Sp.sm),
                ],
                if (config.canDefer) ...[
                  TextButton(
                    onPressed: onLater,
                    child: const Text('稍后'),
                  ),
                  const SizedBox(width: Sp.sm),
                ],
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('重试'),
                ),
              ],
            ),
          ],
        );
    }
  }

  static bool _hasSize(VersionDecision decision) {
    final size = decision.size;
    return size != null && size > 0;
  }

  /// `新版本 1.2.0`（没有版本名就退化成只有标题）。
  static String? versionLabel(VersionDecision decision) {
    final name = decision.latestName;
    if (name == null || name.isEmpty) return null;
    return '新版本 $name';
  }

  /// 更新说明按 `\n` 分行；去掉首尾空白与空行（后台编辑容易留空行）。
  static List<String> splitNotes(String? notes) {
    if (notes == null) return const [];
    return notes
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }
}

/// 有状态外壳：驱动「提示 → 下载 → 校验 → 安装 → 关闭」。
///
/// 失败时留在弹窗里给 [重试]；被拒未知来源权限时给 [去设置]。
class UpdateFlowDialog extends StatefulWidget {
  const UpdateFlowDialog({
    super.key,
    required this.decision,
    required this.installer,
  });

  final VersionDecision decision;
  final ApkInstaller installer;

  @override
  State<UpdateFlowDialog> createState() => _UpdateFlowDialogState();
}

class _UpdateFlowDialogState extends State<UpdateFlowDialog> {
  UpdateDialogPhase _phase = UpdateDialogPhase.prompt;
  DownloadProgress? _progress;
  String? _error;
  bool _showSettingsAction = false;

  bool get _busy =>
      _phase == UpdateDialogPhase.downloading ||
      _phase == UpdateDialogPhase.verifying;

  void _later() => Navigator.of(context).pop();

  Future<void> _start() async {
    if (_busy) return;
    final url = widget.decision.downloadUrl;
    if (url == null || url.isEmpty) {
      setState(() {
        _phase = UpdateDialogPhase.failed;
        _showSettingsAction = false;
        _error = '服务器未提供下载地址，请联系站点管理员';
      });
      return;
    }

    setState(() {
      _phase = UpdateDialogPhase.downloading;
      _progress = null;
      _error = null;
      _showSettingsAction = false;
    });

    final result = await widget.installer.downloadAndInstall(
      url: url,
      expectedSha256: widget.decision.sha256,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
      onVerifying: () {
        if (!mounted) return;
        setState(() => _phase = UpdateDialogPhase.verifying);
      },
    );

    if (!mounted) return;
    switch (result.status) {
      case InstallStatus.launched:
        // 系统安装器已拉起：弹窗使命完成（强制更新时也关掉，
        // 否则用户装完回来还是关不掉的弹窗）。
        Navigator.of(context).pop(result);
      case InstallStatus.permissionDenied:
        setState(() {
          _phase = UpdateDialogPhase.failed;
          _showSettingsAction = true;
          _error = result.message ?? '需要允许安装未知来源应用';
        });
      case InstallStatus.cancelled:
        // 取消：可选更新回到提示态；强制更新留在弹窗（用户必须更新）。
        if (UpdateDialogConfig.from(widget.decision).canDefer) {
          setState(() {
            _phase = UpdateDialogPhase.prompt;
            _progress = null;
          });
        } else {
          setState(() {
            _phase = UpdateDialogPhase.failed;
            _showSettingsAction = false;
            _error = '更新已取消，请重试';
          });
        }
      case InstallStatus.failed:
      case InstallStatus.launchFailed:
        setState(() {
          _phase = UpdateDialogPhase.failed;
          _showSettingsAction = false;
          _error = result.message ?? '下载失败，请重试';
        });
    }
  }

  Future<void> _openSettings() async {
    await widget.installer.openInstallSettings();
    // 从设置页回来后再判一次：授权了就直接装（复用已校验的包），
    // 没授权则留在原样，用户可再次点 [去设置]。
    if (!mounted) return;
    if (await widget.installer.canInstall()) {
      if (!mounted) return;
      await _start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return UpdateDialog(
      decision: widget.decision,
      phase: _phase,
      progress: _progress,
      errorMessage: _error,
      onInstall: _start,
      onLater: _later,
      onRetry: _start,
      onOpenSettings: _showSettingsAction ? _openSettings : null,
    );
  }
}

/// 弹窗弹出动效：400ms spring + 背景压暗（ui-glass-motion §3.2 #16）。
///
/// 走 [Motion] 常量，避免各处硬编码时长。
Route<T> updateDialogRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    transitionDuration: Motion.panel,
    reverseTransitionDuration: Motion.small,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.spring);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
