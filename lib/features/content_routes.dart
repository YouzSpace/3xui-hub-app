import 'package:go_router/go_router.dart';

import 'announcements/announcements_routes.dart';
import 'invite/invite_routes.dart';
import 'tutorials/tutorials_routes.dart';

/// M7 全部路由的汇合点。
///
/// 并行开发期间各模块只导出自己的 `List<GoRoute>`，最后由
/// `core/router/app_router.dart` 统一 import 本文件即可：
///
/// ```dart
/// routes: [
///   ...,
///   ...contentRoutes(),   // M7 邀请 / 教程 / 公告
/// ],
/// ```
///
/// 注意：`/invite` 在 AppShell 里是第 4 个 tab，接入时若使用
/// StatefulShellBranch，应把 `inviteRoutes()` 的第一条放进该分支，
/// 而不是重复注册同名路径。
List<GoRoute> contentRoutes() => [
      ...inviteRoutes(),
      ...tutorialRoutes(),
      ...announcementRoutes(),
    ];
