import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/motion.dart';

/// 全局页面转场（T1.13，ui-glass-motion.md §3.4）。
///
/// 转场集中在路由文件里定义，页面自己不管：
/// - 一级页面（Tab 间）：淡入 + 上移 8dp
/// - 二级页面（详情、设置子页）：右侧滑入
/// - 弹层：背后缩 0.92 + 压暗（由 [scaleBackdrop] 提供给弹层路由使用）
class AppTransitions {
  AppTransitions._();

  /// 一级页面：淡入 + 上移 8dp。
  static CustomTransitionPage<void> fadeLift({
    required Widget child,
    required GoRouterState state,
  }) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: Motion.page,
      reverseTransitionDuration: Motion.page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Motion.emphasized);
        return FadeTransition(
          opacity: curved,
          child: AnimatedBuilder(
            animation: curved,
            builder: (context, widget) => Transform.translate(
              offset: Offset(0, 8 * (1 - curved.value)),
              child: widget,
            ),
            child: child,
          ),
        );
      },
    );
  }

  /// 二级页面：右侧滑入。
  static CustomTransitionPage<void> slideFromRight({
    required Widget child,
    required GoRouterState state,
  }) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: Motion.page,
      reverseTransitionDuration: Motion.page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Motion.emphasized);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: curved.drive(
              Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }

  /// 弹层：内容从 0.92 缩放弹出（spring 回弹），背后压暗渐入。
  ///
  /// 注意：go_router 只能转场新路由自身，「背后页面缩 0.92」由弹层
  /// （M6 购买面板 / M8 更新弹窗）挂载时用同一常量对宿主页面施加。
  static CustomTransitionPage<void> scaleBackdrop({
    required Widget child,
    required GoRouterState state,
  }) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: Motion.panel,
      reverseTransitionDuration: Motion.panel,
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Motion.spring);
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: curved,
            builder: (context, widget) => Transform.scale(
              scale: 0.92 + 0.08 * curved.value,
              child: widget,
            ),
            child: child,
          ),
        );
      },
    );
  }
}
