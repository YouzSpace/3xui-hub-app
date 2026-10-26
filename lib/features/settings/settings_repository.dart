import '../../core/network/api_client.dart';
import '../../core/storage/prefs.dart';
import 'site_config.dart';

/// 设置相关接口（T8.1）：站点配置。
///
/// 铁律：网络请求只出现在仓库层，Widget 不碰 dio。
class SettingsRepository {
  SettingsRepository({ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// GET /api/site-config（公开）。拿到就写 prefs 缓存，下次首帧直接用。
  Future<SiteConfig> fetchSiteConfig() async {
    final data = await _client.request('/api/site-config');
    final config = SiteConfig.fromJson(data);
    if (config.isNotEmpty) {
      // 缓存失败不影响本次展示。
      try {
        await Prefs.setCacheSiteConfig(config.encode());
      } catch (_) {}
    }
    return config;
  }
}
