import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/utils/formatters.dart';

void main() {
  group('formatBytes', () {
    test('0 与负数 → 0 B', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-5), '0 B');
    });

    test('字节直接展示', () {
      expect(formatBytes(512), '512 B');
    });

    test('KB / MB 1024 进制保留 1 位小数', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
    });

    test('GB：1234567890 → 1.1 GB', () {
      expect(formatBytes(1234567890), '1.1 GB');
    });

    test('超大值封顶 PB 不越界', () {
      // 1024 PB 会溢出单位表，应停留在 PB。
      final pb = 1024 * 1024 * 1024 * 1024 * 1024;
      expect(formatBytes(pb * 8), '8.0 PB');
    });
  });

  group('formatMoney', () {
    test('两位小数带货币符', () {
      expect(formatMoney(19.9), '¥19.90');
      expect(formatMoney(0), '¥0.00');
      expect(formatMoney(128), '¥128.00');
    });
  });

  group('formatDate', () {
    test('null → 占位符', () {
      expect(formatDate(null), '—');
    });

    test('UTC 时刻按本地日期格式化', () {
      // 固定时区下验证 yyyy-MM-dd（用 UTC 构造，toLocal 后断言当日本地日期）。
      final d = DateTime.utc(2026, 11, 25, 12);
      final expected =
          '${d.toLocal().year.toString().padLeft(4, '0')}-'
          '${d.toLocal().month.toString().padLeft(2, '0')}-'
          '${d.toLocal().day.toString().padLeft(2, '0')}';
      expect(formatDate(d), expected);
    });
  });

  group('daysLeft', () {
    test('null → 0', () {
      expect(daysLeft(null), 0);
    });

    test('未来日期返回正数', () {
      final future = DateTime.now().add(const Duration(days: 10));
      expect(daysLeft(future), greaterThanOrEqualTo(9));
      expect(daysLeft(future), lessThanOrEqualTo(10));
    });

    test('过期返回负数', () {
      final past = DateTime.now().subtract(const Duration(days: 3));
      expect(daysLeft(past), lessThan(0));
    });
  });

  group('formatDuration', () {
    test('补零 HH:mm:ss', () {
      expect(formatDuration(const Duration(hours: 0, minutes: 12, seconds: 35)),
          '00:12:35');
    });

    test('小时超过两位继续累计', () {
      expect(formatDuration(const Duration(hours: 26, minutes: 5, seconds: 9)),
          '26:05:09');
    });
  });
}
