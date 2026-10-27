import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 服务器地址配置（T9.1 / system-design §10）。
///
/// 域名只允许出现在这一个文件里（grep 卡）。换站点 = 改 defaultValue 一行，
/// 或构建时 `--dart-define=API_BASE=https://客户域名`。
const String kDefaultApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://wujiecloud.top',
);

class ApiConfig {
  static const String _overrideKey = 'api_base_override';

  /// 隐藏入口写入的临时覆盖值（测试/联调用，普通用户不会碰）。
  static String? _override;

  /// 使用时永远走这里，不要直接读 kDefaultApiBase。
  static String get base => _override ?? kDefaultApiBase;

  /// 启动时从 prefs 读 override（通常在 main() 里最先调用）。
  static Future<void> loadOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_overrideKey);
    _override = (v == null || v.isEmpty) ? null : v;
  }

  /// 写入 override；传 null 或空串恢复内置地址。
  static Future<void> setOverride(String? url) async {
    _override = (url == null || url.isEmpty) ? null : url;
    final prefs = await SharedPreferences.getInstance();
    if (_override == null) {
      await prefs.remove(_overrideKey);
    } else {
      await prefs.setString(_overrideKey, _override!);
    }
  }

  /// 校验地址连通性：GET {url}/api/ping，2 秒超时。返回 false = 不通。
  static Future<bool> validate(String url) async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: url,
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 2),
        // 订阅/校验这类纯文本响应不需要统一解包
        responseType: ResponseType.json,
      ));
      final res = await dio.get<dynamic>('/api/ping');
      if (res.data is Map) {
        final map = res.data as Map;
        if (map['code'] == 0) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
