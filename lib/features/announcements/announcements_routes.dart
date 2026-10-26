import 'package:go_router/go_router.dart';

import '../../core/router/transitions.dart';
import 'announcements_page.dart';

/// M7 公告路由（由 app_router.dart 汇总时合并）。
List<GoRoute> announcementRoutes() => [
      GoRoute(
        path: '/announcements',
        pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state,
          child: const AnnouncementsPage(),
        ),
      ),
    ];
