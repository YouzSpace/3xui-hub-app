import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/utils/formatters.dart';
import 'package:controlhub_app/data/models/money.dart';

void main() {
  group('Money.parse（金额口径 = 元，对齐 Go/PHP 实现）', () {
    test('int / double / String 三种输入等价', () {
      expect(Money.parse(19).cents, 1900);
      expect(Money.parse(19.9).cents, 1990);
      expect(Money.parse('19.9').cents, 1990);
      expect(Money.parse('19.90').cents, 1990);
      expect(Money.parse(0).cents, 0);
    });

    test('浮点误差不渗出：19.9 * 100 走字符串解析仍是 1990', () {
      // 直接 (19.9 * 100).round() 恰好也能得到 1990，但 0.29 / 1.15 这类
      // 二进制不可精确表示的值用十进制解析才不会错一分。
      expect(Money.parse(0.29).cents, 29);
      expect(Money.parse(1.15).cents, 115);
      expect(Money.parse(88.65).cents, 8865);
    });

    test('后端实测值：98.5 / 88.0 / 0', () {
      expect(Money.parse(98.5).text, '98.50');
      expect(Money.parse(88.0).text, '88.00');
      expect(Money.parse(0).text, '0.00');
    });

    test('非法值归零，不抛异常', () {
      expect(Money.parse(null).cents, 0);
      expect(Money.parse('').cents, 0);
      expect(Money.parse('abc').cents, 0);
      expect(Money.parse('1e3').cents, 0); // 科学计数法不是 decimal 文本
      expect(Money.parse(double.nan).cents, 0);
      expect(Money.parse(double.infinity).cents, 0);
      expect(Money.parse(true).cents, 0);
    });

    test('三位小数四舍五入到分', () {
      // 19.999 → 19.99 + 第三位 9 → 进位 2000 分。
      expect(Money.parse('19.999').cents, 2000);
      // 19.994 → 第三位 4 → 舍去，1999 分（不是 1994）。
      expect(Money.parse('19.994').cents, 1999);
    });

    test('负数与正号', () {
      expect(Money.parse('-5.5').cents, -550);
      expect(Money.parse('+5.5').cents, 550);
      expect(Money.parse('-0.01').text, '-0.01');
    });

    test('display / text 格式', () {
      expect(Money.parse(19.9).display, '¥19.90');
      expect(Money.parse(0).display, '¥0.00');
      expect(Money.parse(128).text, '128.00');
    });

    test('与 formatMoney 同口径（UI 只用 formatMoney）', () {
      final m = Money.parse('88.65');
      expect(formatMoney(m.yuan), m.display);
    });
  });

  group('Money.applyRate（折后价 = round(元 * rate, 2)，对齐后端）', () {
    test('9 折：98.50 × 0.90 = 88.65', () {
      expect(Money.parse(98.5).applyRate(0.9).text, '88.65');
    });

    test('整数分边界：0.35 × 0.70 = 0.245 → 0.25（half-up）', () {
      expect(Money.parse(0.35).applyRate(0.7).text, '0.25');
    });

    test('rate 非法（负数 / NaN）→ 0，不产生负金额', () {
      expect(Money.parse(10).applyRate(-0.5).cents, 0);
      expect(Money.parse(10).applyRate(double.nan).cents, 0);
    });

    test('加减比较', () {
      final a = Money.parse(10);
      final b = Money.parse('2.50');
      expect((a - b).text, '7.50');
      expect((a + b).text, '12.50');
      expect(a > b, isTrue);
      expect(b >= Money.parse('2.5'), isTrue);
    });

    test('isZero 用于免费套餐分支', () {
      expect(Money.parse(0).isZero, isTrue);
      expect(Money.parse('0.00').isZero, isTrue);
      expect(Money.parse('0.01').isZero, isFalse);
    });
  });

  group('Money.fromCents', () {
    test('分转元展示', () {
      expect(Money.fromCents(1990).display, '¥19.90');
      expect(Money.fromCents(5).text, '0.05');
      expect(Money.fromCents(0).text, '0.00');
    });
  });
}
