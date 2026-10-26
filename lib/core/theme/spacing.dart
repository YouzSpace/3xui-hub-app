/// 间距系统：8dp 基准（design-tokens.md §4）。
///
/// 固定常量统一收口在这里，页面里禁止出现魔法数字。
abstract class Sp {
  static const double xs = 4; // 图标与文字间隙
  static const double sm = 8; // 紧凑元素内间距
  static const double md = 12; // 列表项内垂直 padding
  static const double base = 16; // 页面左右边距、卡片内 padding
  static const double lg = 24; // 分区间隔、卡片大 padding
  static const double xl = 32; // 大区块间隔
  static const double xxl = 48; // 页面顶部留白

  /// 最小触控区边长（MD3 无障碍要求）。
  static const double minTouch = 48;
}
