import 'package:flutter/material.dart';

/// 连点计数（T9.4 隐藏地址入口的触发逻辑，抽成纯类便于单测）。
///
/// 规则：5 次以内、相邻两次点击间隔不超过 [window]，计数累加；
/// 超时或打断（中途间隔过久）就从头数。达到 [required] 次即触发一次并清零，
/// 避免第 6 次点击又立刻触发第二遍。
class TapCounter {
  TapCounter({this.required = 5, this.window = const Duration(seconds: 2)});

  final int required;
  final Duration window;

  int _count = 0;
  DateTime? _lastTap;

  int get count => _count;

  /// 记一次点击；返回 true 表示本次点击刚好凑满次数（调用方据此弹窗）。
  ///
  /// [now] 可注入，单测用它模拟时间间隔。
  bool tap({DateTime? now}) {
    final at = now ?? DateTime.now();
    final last = _lastTap;
    if (last != null && at.difference(last) > window) {
      _count = 0;
    }
    _lastTap = at;
    _count++;
    if (_count >= required) {
      _count = 0;
      _lastTap = null;
      return true;
    }
    return false;
  }

  void reset() {
    _count = 0;
    _lastTap = null;
  }
}

/// 包在版本号外面，连点 [required] 次后回调 [onTriggered]。
///
/// 用 `GestureDetector` 而不是 `InkWell`：版本号是展示文字不是按钮，
/// 不做水波纹（隐藏入口不该有视觉提示）。
class VersionTapTrigger extends StatefulWidget {
  const VersionTapTrigger({
    super.key,
    required this.child,
    required this.onTriggered,
    this.required = 5,
  });

  final Widget child;
  final VoidCallback onTriggered;
  final int required;

  @override
  State<VersionTapTrigger> createState() => _VersionTapTriggerState();
}

class _VersionTapTriggerState extends State<VersionTapTrigger> {
  late final TapCounter _counter = TapCounter(required: widget.required);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_counter.tap()) widget.onTriggered();
      },
      child: widget.child,
    );
  }
}
