/// 展示格式化工具（T1.8）。
///
/// 全部纯函数，可单测。数字统一用等宽样式在 UI 层处理（tabularFigures）。
library;

/// 流量：1024 进制，保留 [fractionDigits] 位小数（默认 2）。`1234567890` → `1.15 GB`。
String formatBytes(int bytes, {int fractionDigits = 2}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  if (i == 0) return '$bytes B';
  return '${value.toStringAsFixed(fractionDigits)} ${units[i]}';
}

/// 金额：`¥19.90`（两位小数）。
String formatMoney(num value) => '¥${value.toStringAsFixed(2)}';

/// 日期：`2026-11-25`；null → `—`。
String formatDate(DateTime? d) {
  if (d == null) return '—';
  final t = d.toLocal();
  final y = t.year.toString().padLeft(4, '0');
  final m = t.month.toString().padLeft(2, '0');
  final day = t.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// 剩余天数（按自然日）；已过期返回负数；null 返回 0。
int daysLeft(DateTime? d) {
  if (d == null) return 0;
  final t = d.toLocal();
  final target = DateTime(t.year, t.month, t.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return target.difference(today).inDays;
}

/// 时长：`00:12:35`（HH:mm:ss，小时可超两位）。
String formatDuration(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}
