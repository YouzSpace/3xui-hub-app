import 'dart:math' as math;

import '../data/models/user_profile.dart';

/// 流量卡片三种形态（T5.3）。
enum TrafficPlanState { thirdParty, noPlan, normal }

/// 流量卡片的纯数据投影（可单测，不依赖 Widget）。
///
/// 判定顺序：先「未订阅」再「第三方套餐」—— 后端对无套餐用户也会下发
/// `plan_include_local: false`，反过来会把未订阅误判成第三方套餐。
class TrafficSummary {
  const TrafficSummary({
    required this.state,
    required this.planName,
    required this.used,
    required this.limit,
    required this.expiredAt,
    required this.resetAt,
  });

  final TrafficPlanState state;
  final String planName;

  /// 本月已用字节数。
  final int used;

  /// 本月流量上限；0 表示不限量。
  final int limit;

  final DateTime? expiredAt;
  final DateTime? resetAt;

  factory TrafficSummary.fromProfile(UserProfile profile) {
    final TrafficPlanState state;
    if (profile.planId == 0) {
      state = TrafficPlanState.noPlan;
    } else if (!profile.planIncludeLocal) {
      state = TrafficPlanState.thirdParty;
    } else {
      state = TrafficPlanState.normal;
    }
    return TrafficSummary(
      state: state,
      planName: profile.planName,
      used: profile.monthlyTrafficUsed,
      limit: profile.monthlyTrafficLimit,
      expiredAt: profile.expiredAt,
      resetAt: profile.nextTrafficResetAt,
    );
  }

  bool get isUnlimited => limit <= 0;

  /// 进度 0..1；不限量返回 null（进度条隐藏）。
  double? get progress => isUnlimited ? null : (used / limit).clamp(0.0, 1.0);

  int get remaining => isUnlimited ? 0 : math.max(0, limit - used);

  /// 超过 90% → 进度条转 error 色 + 「流量即将用完」。
  bool get isNearLimit {
    final p = progress;
    return p != null && p > 0.9;
  }
}
