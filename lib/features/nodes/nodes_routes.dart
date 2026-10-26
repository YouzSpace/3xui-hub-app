import 'package:go_router/go_router.dart';

import '../../core/router/transitions.dart';
import 'nodes_page.dart';

/// M3 路由（T3.5）。
///
/// 边界铁律：M3 只导出这个 `List<GoRoute>`，**绝不改** `lib/core/router/app_router.dart`
/// —— 并行期间其他 agent 也在改它，最后由汇总方把 [nodesRoutes] 拼进总表。
///
/// 路径约定与 app_router.dart 现有占位页一致（`/nodes` 是底部 Tab 分支），
/// 汇总时直接替换该分支的占位页即可。
abstract class NodesRoutes {
  static const nodes = '/nodes';
}

/// M3 的所有路由，交给汇总方拼进 `app_router.dart`。
final List<GoRoute> nodesRoutes = [
  GoRoute(
    path: NodesRoutes.nodes,
    pageBuilder: (context, state) =>
        AppTransitions.fadeLift(state: state, child: const NodesPage()),
  ),
];
