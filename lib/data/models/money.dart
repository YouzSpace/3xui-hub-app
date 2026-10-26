/// 金额口径（T6.1，system-design §3.5/§3.6）。
///
/// **实测结论（2026-10-26，`server/internal/handler/api/`）**：Go 端 `plan.price` /
/// `order.amount` 走 `phpFloat`（`json.Marshal` 的 float64），PHP 端是 `(float) $order->amount`，
/// 两边**都是「元」**（19.9 / 88.65），不是分。tasks/06_purchase.md 里写的「金额单位：分」
/// 与两端实现都不符，以真实实现为准（任务书要求「不确定就核对 handler，禁止猜」）。
///
/// 全项目只在 [Money] 和 `formatMoney` 里处理金额的整数化，避免 0.1+0.2 的浮点误差
/// 渗进「折后价」「已优惠」这类要约性质的计算。
library;

import '../../core/network/api_exception.dart';

/// 金额（元），内部用「分」存整数，杜绝浮点累加误差。
class Money implements Comparable<Money> {
  /// 内部最小单位：分。
  final int cents;

  const Money._(this.cents);

  /// 零元。
  static const Money zero = Money._(0);

  /// 从「分」构造（仅用于测试与显式换算）。
  const Money.fromCents(this.cents);

  /// 容错解析：后端可能给 int / double / String（decimal 文本）。
  ///
  /// 走字符串中转而不是 `(v * 100).round()`：`19.9 * 100` 在 binary64 下是
  /// 1989.9999…，`round()` 只是碰巧把它救回来；解析十进制字符串则是精确的。
  factory Money.parse(dynamic v) {
    if (v is int) return Money._(v * 100);
    if (v is double) {
      if (!v.isFinite) return zero;
      return Money.parse(v.toString());
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return zero;
      var body = s;
      var negative = false;
      if (body.startsWith('-')) {
        negative = true;
        body = body.substring(1);
      } else if (body.startsWith('+')) {
        body = body.substring(1);
      }
      final dot = body.indexOf('.');
      var intPart = dot < 0 ? body : body.substring(0, dot);
      var fracPart = dot < 0 ? '' : body.substring(dot + 1);
      if (intPart.isEmpty && fracPart.isEmpty) return zero;
      if (intPart.isEmpty) intPart = '0';
      // 超过两位的小数：先按四舍五入截断（后端 decimal(10,2) 不会给出这种值）。
      if (fracPart.length > 2) {
        final third = fracPart.codeUnitAt(2) - 0x30;
        fracPart = fracPart.substring(0, 2);
        final parsed = _digitsToCents(intPart, fracPart);
        if (parsed == null) return zero;
        return Money._(_applySign(
          third >= 5 ? parsed + 1 : parsed,
          negative,
        ));
      }
      final parsed = _digitsToCents(intPart, fracPart);
      if (parsed == null) return zero;
      return Money._(_applySign(parsed, negative));
    }
    return zero;
  }

  static int _applySign(int cents, bool negative) =>
      negative ? -cents : cents;

  /// 纯数字校验后再累加，避免 `int.parse('1e3')` 之类的意外放行。
  static int? _digitsToCents(String intPart, String fracPart) {
    for (var i = 0; i < intPart.length; i++) {
      final c = intPart.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return null;
    }
    for (var i = 0; i < fracPart.length; i++) {
      final c = fracPart.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return null;
    }
    var value = 0;
    for (var i = 0; i < intPart.length; i++) {
      value = value * 10 + (intPart.codeUnitAt(i) - 0x30);
      // 10^12 元已经远超 decimal(10,2) 的上限，防溢出到无意义区间。
      if (value > 1000000000000) return null;
    }
    final frac = fracPart.padRight(2, '0');
    return value * 100 +
        (frac.codeUnitAt(0) - 0x30) * 10 +
        (frac.codeUnitAt(1) - 0x30);
  }

  /// 折扣率（0.90 表示 9 折）：与后端 `round(original * rate, 2)` 同口径。
  Money applyRate(double rate) {
    if (!rate.isFinite || rate < 0) return zero;
    // 后端是 round(元 * rate, 2)；这里在「分」上算，round 用 half-up
    // （Dart 的 round() 对 .5 是远离零，与 PHP round() 默认行为一致）。
    final y = (cents * rate).round();
    return Money._(y);
  }

  Money operator +(Money other) => Money._(cents + other.cents);

  Money operator -(Money other) => Money._(cents - other.cents);

  bool operator >(Money other) => cents > other.cents;

  bool operator <(Money other) => cents < other.cents;

  bool operator >=(Money other) => cents >= other.cents;

  bool operator <=(Money other) => cents <= other.cents;

  /// 元（浮点）：只给 display 以外的第三方 API 用，UI 一律走 [formatMoney]。
  double get yuan => cents / 100;

  /// `19.90`（无货币符）。
  String get text {
    final negative = cents < 0;
    final abs = negative ? -cents : cents;
    final intPart = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$intPart.$frac';
  }

  /// `¥19.90`。
  String get display => '¥$text';

  /// 是否为免费（价格 0 的套餐下单后直接 paid）。
  bool get isZero => cents == 0;

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  String toString() => 'Money($text)';
}

/// 数字字段容错：int / double / String → int，非法值归 0。
///
/// 与 `UserProfile._toInt` 同口径（后端同一批字段可能是 int、double 或 "3"）。
int jsonInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) {
    final parsed = num.tryParse(v.trim());
    if (parsed != null) return parsed.toInt();
  }
  return 0;
}

/// 数字字段容错，但**保留 null**：`total_traffic` 实测可能返回 `null`
/// （system-design §3.5 明确要求可空类型，不能当 0）。
int? jsonIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  if (v is String) {
    final parsed = num.tryParse(v.trim());
    if (parsed != null) return parsed.toInt();
  }
  return null;
}

/// 字符串字段容错：非字符串一律空串。
String jsonStr(dynamic v) => v is String ? v : '';

/// 时间字段容错：ISO8601 解析失败返回 null，不抛异常。
DateTime? jsonDate(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v)?.toLocal();
}

/// 对象整包非法（缺主键/结构不对）时抛的错误，与 M2 的 UserProfile 同口径。
Never throwParseError() =>
    throw const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
