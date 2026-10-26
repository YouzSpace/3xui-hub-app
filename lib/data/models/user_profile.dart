import '../../core/network/api_exception.dart';

/// 我的信息（system-design §3.3，GET /api/me 的 data）。
///
/// 注意：`token` 是订阅 token（拼订阅 URL 用），不是 access_token，
/// 两者绝不能混用。
class UserProfile {
  final int id;
  final String email;

  /// 订阅 token（非 access_token）。
  final String token;
  final String protocol;
  final int planId;
  final String planType;
  final String planName;
  final bool planIncludeLocal;
  final int planMonths;
  final double planPrice;
  final double planResetPrice;
  final int trafficLimit;
  final int trafficUsed;
  final int monthlyTrafficUsed;
  final int monthlyTrafficLimit;
  final DateTime? nextTrafficResetAt;
  final DateTime? expiredAt;
  final bool enabled;

  const UserProfile({
    required this.id,
    required this.email,
    required this.token,
    required this.protocol,
    required this.planId,
    required this.planType,
    required this.planName,
    required this.planIncludeLocal,
    required this.planMonths,
    required this.planPrice,
    required this.planResetPrice,
    required this.trafficLimit,
    required this.trafficUsed,
    required this.monthlyTrafficUsed,
    required this.monthlyTrafficLimit,
    required this.nextTrafficResetAt,
    required this.expiredAt,
    required this.enabled,
  });

  /// 容错解析：数值字段后端可能是 int/double/String；时间字段
  /// ISO8601 解析失败返回 null 不抛异常；整包非法抛 ApiException(codeParse)。
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    if (json['id'] == null) {
      throw const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
    }
    return UserProfile(
      id: _toInt(json['id']),
      email: _toStr(json['email']),
      token: _toStr(json['token']),
      protocol: _toStr(json['protocol']),
      planId: _toInt(json['plan_id']),
      planType: _toStr(json['plan_type']),
      planName: _toStr(json['plan_name']),
      planIncludeLocal: json['plan_include_local'] == true,
      planMonths: _toInt(json['plan_months']),
      planPrice: _toDouble(json['plan_price']),
      planResetPrice: _toDouble(json['plan_reset_price']),
      trafficLimit: _toInt(json['traffic_limit']),
      trafficUsed: _toInt(json['traffic_used']),
      monthlyTrafficUsed: _toInt(json['monthly_traffic_used']),
      monthlyTrafficLimit: _toInt(json['monthly_traffic_limit']),
      nextTrafficResetAt: _toDateTime(json['next_traffic_reset_at']),
      expiredAt: _toDateTime(json['expired_at']),
      enabled: json['enabled'] != false,
    );
  }

  static int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) {
      final parsed = num.tryParse(v);
      if (parsed != null) return parsed.toInt();
    }
    return 0;
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) {
      final parsed = double.tryParse(v);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  static String _toStr(dynamic v) => v is String ? v : '';

  /// ISO8601 解析失败返回 null，不抛异常（tasks/02_auth.md T2.1）。
  static DateTime? _toDateTime(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }
}
