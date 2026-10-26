import '../../core/network/api_client.dart';
import '../models/site_content.dart';

/// 站点内容仓库（M7 用到的 site-config 子集）。
///
/// 公告与反馈链接都来自 GET /api/site-config（proposal F13/F14），
/// 后端没有独立的公告接口。
class ContentRepository {
  ContentRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<SiteContent> fetchSiteContent() async {
    final data = await _client.request('/api/site-config');
    if (data is! Map) {
      return const SiteContent(
        siteTitle: '',
        announcement: '',
        feedbackLink: '',
      );
    }
    return SiteContent.fromJson(Map<String, dynamic>.from(data));
  }
}
