import 'dart:convert';

/// 站点配置（system-design §3.1，`GET /api/site-config`）。
///
/// 后端所有值都是**字符串**（`"0"`/`"1"` 表示开关），所以这里统一存成
/// `Map<String, String>`，判断一律按字符串比较，不做 bool 转换。
class SiteConfig {
  const SiteConfig(this.values);

  static const SiteConfig empty = SiteConfig(<String, String>{});

  final Map<String, String> values;

  String get siteTitle => _get('site_title');
  String get siteSubtitle => _get('site_subtitle');
  String get announcement => _get('announcement');

  /// 意见反馈外链（T7.4：非空才显示入口）。
  String get feedbackLink => _get('feedback_link');

  bool get isNotEmpty => values.isNotEmpty;

  String _get(String key) => (values[key] ?? '').trim();

  /// 只保留字符串值；数字/布尔也转字符串（后端未来改类型不会炸）。
  factory SiteConfig.fromJson(Object? data) {
    if (data is! Map) return SiteConfig.empty;
    final out = <String, String>{};
    data.forEach((key, value) {
      if (key is String) out[key] = value?.toString() ?? '';
    });
    return SiteConfig(out);
  }

  /// prefs 缓存解码：坏数据按空配置处理（站点信息缺失不该影响设置页）。
  factory SiteConfig.decode(String? raw) {
    if (raw == null || raw.isEmpty) return SiteConfig.empty;
    try {
      return SiteConfig.fromJson(jsonDecode(raw));
    } catch (_) {
      return SiteConfig.empty;
    }
  }

  String encode() => jsonEncode(values);
}
