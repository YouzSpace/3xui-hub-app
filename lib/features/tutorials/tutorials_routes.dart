import 'package:go_router/go_router.dart';

import '../../core/router/transitions.dart';
import 'tutorial_detail_page.dart';
import 'tutorials_page.dart';

/// M7 教程路由（由 app_router.dart 汇总时合并）。
List<GoRoute> tutorialRoutes() => [
      GoRoute(
        path: '/tutorials',
        pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state,
          child: const TutorialsPage(),
        ),
      ),
      GoRoute(
        path: '/tutorials/:id',
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return AppTransitions.slideFromRight(
            state: state,
            child: TutorialDetailPage(id: id),
          );
        },
      ),
    ];
