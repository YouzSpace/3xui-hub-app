import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/prefs.dart';
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

/// 站点内容：启动先读本地缓存立即渲染（避免先显示空/占位再闪成网站名与 logo），
/// 后台网络刷新成功后写回缓存。无缓存且网络失败才进入 error。
final siteContentProvider =
    StateNotifierProvider<SiteContentNotifier, AsyncValue<SiteContent>>(
  (ref) => SiteContentNotifier(ref.read(contentRepositoryProvider)),
);

class SiteContentNotifier extends StateNotifier<AsyncValue<SiteContent>> {
  SiteContentNotifier(this._repo, {bool autoLoad = true})
      : super(const AsyncValue.loading()) {
    if (autoLoad) _load();
  }

  final ContentRepository _repo;

  Future<void> _load() async {
    // 1. 先读本地缓存立即渲染。
    final cached = await Prefs.getCacheSiteConfig();
    if (cached != null && cached.isNotEmpty) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(cached) as Map);
        state = AsyncValue.data(SiteContent.fromJson(map));
      } catch (_) {
        // 缓存损坏则忽略，走网络。
      }
    }
    // 2. 网络刷新，成功后写缓存。
    try {
      final fresh = await _repo.fetchSiteContent();
      state = AsyncValue.data(fresh);
      await Prefs.setCacheSiteConfig(jsonEncode(fresh.toJson()));
    } catch (e) {
      // 已有缓存就继续用缓存，不打扰用户；无缓存才进入错误态。
      if (!state.hasValue) {
        state = AsyncValue.error(e, StackTrace.current);
      }
    }
  }
}
