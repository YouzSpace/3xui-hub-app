import 'package:go_router/go_router.dart';

import '../../core/router/transitions.dart';
import 'invite_page.dart';

/// M7 邀请路由（由 app_router.dart 汇总时合并，本文件不改公共路由表）。
List<GoRoute> inviteRoutes() => [
      GoRoute(
        path: '/invite',
        pageBuilder: (context, state) => AppTransitions.fadeLift(
          state: state,
          child: const InvitePage(),
        ),
      ),
    ];
