import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import '../../vpn/blocked_apps.dart';
import 'settings_providers.dart';
import 'split_tunnel_widgets.dart';

/// 分应用代理（T8.2）：勾选的应用**不走代理**（bypass）。
///
/// 数据层直接复用 M4 的 [installedAppsProvider] / [blockedAppsProvider]，
/// 不重写 MethodChannel；本页只负责搜索、勾选和保存。
class SplitTunnelPage extends ConsumerStatefulWidget {
  const SplitTunnelPage({super.key});

  @override
  ConsumerState<SplitTunnelPage> createState() => _SplitTunnelPageState();
}

class _SplitTunnelPageState extends ConsumerState<SplitTunnelPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  /// 编辑中的选择（保存前不落盘，返回即丢弃）。
  late Set<String> _selected;

  /// 用户动过勾选后，不再被 provider 的异步回填覆盖。
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 进页面时取一次快照：prefs 回填可能还在路上（main 里 unawaited），
    // 由 build 里的 listen 在用户未动手前补上。
    _selected = ref.read(blockedAppsProvider).toSet();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggle(String packageName, bool selected) {
    setState(() {
      _dirty = true;
      if (selected) {
        _selected.add(packageName);
      } else {
        _selected.remove(packageName);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final wasConnected = ref.read(vpnConnectedProvider);
    try {
      await ref
          .read(blockedAppsProvider.notifier)
          .setApps(_selected.toList()..sort());
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败，请重试');
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    // 已连接时改动不会立即生效：引擎只在 start 时读一次 blockedApps。
    _toast(wasConnected ? '已保存，重新连接后生效' : '已保存');
    Navigator.of(context).pop();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<InstalledApp> _filter(List<InstalledApp> apps) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return apps;
    return apps
        .where(
          (a) =>
              a.appName.toLowerCase().contains(query) ||
              a.packageName.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // prefs 回填（main 里 unawaited）晚于本页 initState 时补一次；
    // 用户已经动过勾选就让位，不覆盖编辑内容。
    ref.listen<List<String>>(blockedAppsProvider, (previous, next) {
      if (_dirty || _saving) return;
      setState(() => _selected = next.toSet());
    });

    final apps = ref.watch(installedAppsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('分应用代理'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: Sp.base,
                    height: Sp.base,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: apps.when(
        // 骨架屏放进可滚动容器：小屏/横屏下 6 行会超出视口高度。
        loading: () => ListView(
          padding: const EdgeInsets.all(Sp.base),
          children: const [SkeletonList(count: 6)],
        ),
        error: (_, _) => ErrorView(
          message: '读取已安装应用失败',
          onRetry: () => ref.invalidate(installedAppsProvider),
        ),
        data: (all) {
          if (all.isEmpty) {
            return const EmptyView(
              icon: Icons.apps_outlined,
              text: '没有可选择的已安装应用',
            );
          }
          final shown = _filter(all);
          return Column(
            children: [
              SplitTunnelHeader(selectedCount: _selected.length),
              AppSearchField(
                controller: _searchCtrl,
                // 每次输入都重建列表（数据量百级，无需防抖）。
                onChanged: (_) => setState(() {}),
              ),
              const Divider(height: 1),
              Expanded(
                child: shown.isEmpty
                    ? const EmptyView(icon: Icons.search_off, text: '没有匹配的应用')
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: Sp.lg),
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final app = shown[i];
                          return InstalledAppTile(
                            app: app,
                            selected: _selected.contains(app.packageName),
                            onChanged: (v) => _toggle(app.packageName, v),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
