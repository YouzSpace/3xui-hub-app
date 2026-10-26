import 'package:flutter/animation.dart';

/// 动效常量（ui-glass-motion.md §3.1，唯一来源）。
///
/// 铁律：页面里不许出现 `Duration(milliseconds: 350)` 这种硬编码，
/// 一律引用这里的常量；曲线禁止 `linear`。
abstract class Motion {
  // 时长（按元素大小分级，禁止一刀切）
  static const Duration press = Duration(milliseconds: 60); // 按下
  static const Duration release = Duration(milliseconds: 150); // 松开回弹
  static const Duration small = Duration(milliseconds: 200); // 小元素、状态切换
  static const Duration panel = Duration(milliseconds: 400); // 面板、卡片、抽屉
  static const Duration page = Duration(milliseconds: 500); // 整页转场
  static const Duration max = Duration(milliseconds: 700); // 任何动效上限
  static const Duration splash = Duration(milliseconds: 500); // 开屏过渡总时长

  // 曲线（禁止 linear）
  static const Curve easeOut = Curves.easeOutCubic; // 进场
  static const Curve easeIn = Curves.easeInCubic; // 退场
  static const Curve spring = Curves.easeOutBack; // 回弹（超调约 8%）
  static const Curve emphasized = Cubic(0.2, 0, 0, 1); // MD3 主转场

  // 序列延迟（一组元素依次出现）
  static const Duration stagger = Duration(milliseconds: 40);

  // 循环类动效周期（ui-glass-motion.md §3.2）
  static const Duration shimmer = Duration(milliseconds: 1500); // 骨架扫光
  static const Duration copyReset = Duration(seconds: 2); // 复制变勾恢复

  /// 系统「移除动画」开启时的降级时长（ui-glass-motion.md §3.5：≤150ms）。
  static const Duration reduced = Duration(milliseconds: 150);
}
