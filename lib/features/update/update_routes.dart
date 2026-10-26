import 'package:go_router/go_router.dart';

/// M9B 路由出口（文件边界铁律：本模块不修改 `core/router/app_router.dart`）。
///
/// 升级功能全部是弹窗（`showUpdateDialog`）与设置页内联条目，没有独立页面，
/// 因此这里返回空表 —— 由主路由 `...updateRoutes` 合并也不会产生任何路径。
///
/// 如果将来要加「更新详情」整页（例如强制更新全屏版），在这里返回
/// `GoRoute(path: '/update', ...)`，主路由合并即可，无需改游标。
const List<GoRoute> updateRoutes = <GoRoute>[];
