import 'package:flutter/material.dart';

import '../core/theme/spacing.dart';
import '../core/ui/motion.dart';
import '../vpn/vpn_state.dart';
import 'connect_button_fx.dart';

/// 连接按钮（T5.2，动效严格照 ui-glass-motion.md §3.3）。
///
/// 120dp 圆形三态：
/// - 未连接：`primary` 实心 + power 图标 + 「连接」
/// - 连接中：`primaryContainer` + 进度圈 + 「连接中…」
/// - 已连接：`primary` + 呼吸光晕 + 玻璃外环 + 「已连接」
/// 禁用态（到期/耗尽）：底 `onSurface` 0.12、图标 0.38；点击仍进 [onPressed]，
/// 由页面弹 SnackBar 说明原因（点不动但不知道为什么最糟）。
///
/// 循环周期文档给的是 1.2s / 2s，`Motion` 无对应常量：按「常量唯一来源」
/// 收口在本类，页面里不出现魔法数字。
class ConnectButton extends StatefulWidget {
  const ConnectButton({
    super.key,
    required this.status,
    required this.onPressed,
    this.blockedReason,
    this.blockedIcon = Icons.power_settings_new,
  });

  final VpnStatus status;
  final VoidCallback onPressed;

  /// 非空 = 套餐层面不可连接（到期 / 流量耗尽等），按钮置灰。
  final String? blockedReason;

  /// 禁用态图标（未订阅时换购物车更直白）。
  final IconData blockedIcon;

  /// 连接中外环脉冲周期（1.0 → 1.35 淡出）。
  static const Duration pulse = Duration(milliseconds: 1200);

  /// 已连接呼吸光晕周期。
  static const Duration breathe = Duration(seconds: 2);

  /// 断开时光晕收缩时长。
  static const Duration collapse = Duration(milliseconds: 300);

  /// 直径（§3.3 / §4）。
  static const double diameter = 120;

  /// 按下缩放比（§3.3：0.96）。
  static const double pressedScale = 0.96;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  /// 连接中外环脉冲 + 图标旋转（1.2s 循环）。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: ConnectButton.pulse,
  );

  /// 已连接呼吸光晕（2s 循环，往返）。
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: ConnectButton.breathe,
  );

  bool _pressed = false;

  /// 光晕在场：已连接时 true；断开后先收缩 300ms 再摘掉。
  bool _haloVisible = false;

  bool get _reduced => MediaQuery.of(context).disableAnimations;

  bool get _connecting => widget.status == VpnStatus.preparing ||
      widget.status == VpnStatus.connecting;

  @override
  void initState() {
    super.initState();
    _haloVisible = widget.status == VpnStatus.connected;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoops();
  }

  @override
  void didUpdateWidget(ConnectButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLoops();
  }

  /// 按状态开/停循环动画；系统「移除动画」时一律不开（§3.5）。
  ///
  /// 只在 didChangeDependencies / didUpdateWidget 里调用（build 紧随其后），
  /// 所以这里的字段赋值不需要 setState。
  void _syncLoops() {
    final reduce = _reduced;
    final connected = widget.status == VpnStatus.connected;

    if (_connecting && !reduce) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating) {
      _pulse.stop();
    }

    if (connected) {
      if (!_haloVisible) setState(() => _haloVisible = true);
      if (!reduce && !_halo.isAnimating) _halo.repeat(reverse: true);
    } else if (_haloVisible) {
      if (reduce || _halo.value == 0) {
        _halo.stop();
        setState(() => _haloVisible = false);
      } else {
        // 断开：光晕收缩消失 300ms，然后回未连接态。
        _halo.stop();
        _halo.animateTo(0, duration: ConnectButton.collapse, curve: Motion.easeIn)
            .then((_) {
          if (mounted) setState(() => _haloVisible = false);
        });
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _halo.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final status = widget.status;
    final blocked = widget.blockedReason != null;
    final busy = status == VpnStatus.preparing ||
        status == VpnStatus.connecting ||
        status == VpnStatus.disconnecting;

    final bg = blocked
        ? cs.onSurface.withValues(alpha: 0.12)
        : _connecting
            ? cs.primaryContainer
            : cs.primary;
    final fg = blocked
        ? cs.onSurface.withValues(alpha: 0.38)
        : _connecting
            ? cs.onPrimaryContainer
            : cs.onPrimary;

    final label = switch (status) {
      VpnStatus.preparing || VpnStatus.connecting => '连接中…',
      VpnStatus.disconnecting => '断开中',
      VpnStatus.connected => '已连接',
      _ => '连接',
    };

    // 按下 0.96（60ms），松开回弹（150ms spring）；减少动效时不做缩放。
    final pressed = _pressed && !_reduced;

    return Semantics(
      button: true,
      enabled: !busy,
      label: blocked ? '$label，${widget.blockedReason}' : label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: ConnectButton.diameter,
            height: ConnectButton.diameter,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (_haloVisible)
                  ConnectHaloRing(
                    progress: _halo,
                    diameter: ConnectButton.diameter,
                    reduced: _reduced,
                  ),
                if (_connecting)
                  ConnectPulseRing(
                    progress: _pulse,
                    diameter: ConnectButton.diameter,
                    reduced: _reduced,
                  ),
                AnimatedScale(
                  scale: pressed ? ConnectButton.pressedScale : 1,
                  duration: pressed ? Motion.press : Motion.release,
                  curve: Motion.spring,
                  child: _core(
                    bg: bg,
                    fg: fg,
                    busy: busy,
                    icon: blocked
                        ? widget.blockedIcon
                        : status == VpnStatus.connected
                            ? Icons.check
                            : Icons.power_settings_new,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.md),
          // 文字只做颜色/内容变化（§3.3：时长每秒更新但数字不抖）。
          AnimatedDefaultTextStyle(
            duration: _reduced ? Motion.reduced : Motion.small,
            curve: Motion.easeOut,
            style: text.titleSmall!.copyWith(
              color: blocked ? cs.onSurfaceVariant : cs.primary,
              fontWeight: FontWeight.w600,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }

  /// 圆形本体：点击 + 按下反馈 + 图标 / 进度圈。
  Widget _core({
    required Color bg,
    required Color fg,
    required bool busy,
    required IconData icon,
  }) {
    final reduced = _reduced;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      animationDuration: reduced ? Motion.reduced : Motion.panel,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : widget.onPressed,
        onTapDown: busy || reduced ? null : (_) => _setPressed(true),
        onTapUp: busy || reduced ? null : (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: Center(
          child: AnimatedSwitcher(
            duration: reduced ? Motion.reduced : Motion.small,
            switchInCurve: Motion.easeOut,
            switchOutCurve: Motion.easeIn,
            // 图标切换（电源→√）缩放弹入，让「已连接」一眼可辨。
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: CurvedAnimation(parent: animation, curve: Motion.spring),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: _connecting
                ? SizedBox(
                    key: const ValueKey('progress'),
                    width: Sp.xl,
                    height: Sp.xl,
                    child: CircularProgressIndicator(strokeWidth: 3, color: fg),
                  )
                : RotationTransition(
                    // 连接中图标旋转（1.2s/圈）；静止态锁在 0。
                    // key 用图标区分（电源 vs √），切换时才触发过渡动画。
                    key: ValueKey(icon),
                    turns:
                        _connecting ? _pulse : const AlwaysStoppedAnimation(0),
                    child: Icon(icon, size: Sp.xxl + Sp.base, color: fg),
                  ),
          ),
        ),
      ),
    );
  }
}
