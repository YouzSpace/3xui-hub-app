import 'package:flutter/material.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/spacing.dart';

/// T9.4 隐藏地址入口：连续点击版本号 5 次后弹出。
///
/// 规则（system-design §10.3）：
/// - 输入地址 → `GET /api/ping` 校验（2s 超时）→ 通过才写 override → 提示重启生效
/// - 校验不通过 → 停在弹窗里提示，不写盘
/// - 留空确定 → 清 override，恢复内置地址
/// - 清空后同样提示重启生效（当前进程的 Dio baseUrl 是启动时建的）
///
/// 普通用户永远碰不到这个入口，返回 true 表示地址被改动过。
Future<bool> showHiddenApiBaseDialog(BuildContext context) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => const _ApiBaseDialog(),
  );
  return changed ?? false;
}

class _ApiBaseDialog extends StatefulWidget {
  const _ApiBaseDialog();

  @override
  State<_ApiBaseDialog> createState() => _ApiBaseDialogState();
}

class _ApiBaseDialogState extends State<_ApiBaseDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: ApiConfig.base,
  );

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    // 去掉尾部斜杠：地址拼接统一靠 ApiConfig.base + '/api/xxx'，
    // 留着尾斜杠会让最终 URL 出现双斜杠（部分网关会 404）。
    final raw = _ctrl.text.trim().replaceFirst(RegExp(r'/+$'), '');

    // 留空 = 恢复内置地址，不需要联网校验。
    if (raw.isEmpty) {
      setState(() => _busy = true);
      try {
        await ApiConfig.setOverride(null);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = '保存失败，请重试';
        });
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }

    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => _error = '请输入完整地址（含协议前缀）');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    // 校验走 /api/ping：只有真能连上的地址才允许写入，避免误操作把 App 变砖。
    final ok = await ApiConfig.validate(raw);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = '地址无法连接（/api/ping 校验失败）';
      });
      return;
    }

    try {
      await ApiConfig.setOverride(raw);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '保存失败，请重试';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('服务器地址'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '仅供测试与联调使用。留空保存可恢复内置地址。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: Sp.base),
          TextField(
            controller: _ctrl,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: '服务器地址',
              hintText: '留空则恢复内置地址',
              errorText: _error,
              errorMaxLines: 2,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: Sp.base,
                  height: Sp.base,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
