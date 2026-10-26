import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/site_content.dart';
import '../../data/repositories/content_repository.dart';

/// 站点内容数据源（公告 / 反馈链接 / 站点名），M7 内共享。
///
/// 这三项都来自 GET /api/site-config，后端没有独立公告接口（proposal F13/F14）。
/// 放在 announcements 目录是因为公告是它的主要消费方；邀请页（分享文案要站点名）
/// 与反馈入口（链接）从这里 import，避免各自再定义一份 provider。
final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) => ContentRepository(),
);

final siteContentProvider = FutureProvider<SiteContent>((ref) async {
  return ref.read(contentRepositoryProvider).fetchSiteContent();
});
