import '../../core/network/api_exception.dart';

/// 邀请信息（system-design §3.7，GET /api/invite/me 的 data）。
///
/// 字段以下列 Go 实现为准（`server/internal/handler/api/user_extras.go`）：
/// `{invite_code, invited_count, redeem_codes: [{code, status}]}`。
/// 老 PHP 返回的是嵌套 `invite.code` 且兑换码多 discount/note/expires_at，
/// 这里两者都能解析：多出来的字段有就展示、没有就不占位。
class InviteInfo {
  /// 邀请码；后端未生成时为空串（UI 显示「暂无邀请码」）。
  final String code;
  final int invitedCount;
  final List<RedeemCode> redeemCodes;

  const InviteInfo({
    required this.code,
    required this.invitedCount,
    required this.redeemCodes,
  });

  bool get hasCode => code.isNotEmpty;

  factory InviteInfo.fromJson(Map<String, dynamic> json) {
    final nested = json['invite'];
    final codeRaw = json['invite_code'] ??
        (nested is Map ? nested['code'] : null);
    final codesRaw = json['redeem_codes'];
    final codes = <RedeemCode>[];
    if (codesRaw is List) {
      for (final item in codesRaw) {
        if (item is Map) {
          final parsed = RedeemCode.tryParse(item);
          if (parsed != null) codes.add(parsed);
        }
      }
    }
    return InviteInfo(
      code: _toStr(codeRaw),
      invitedCount: _toInt(json['invited_count']),
      redeemCodes: codes,
    );
  }
}

/// 兑换码（source = redeem 的那批码）。
class RedeemCode {
  final String code;

  /// 折扣系数：0.90 表示 9 折。Go 端未返回该字段，故可空。
  final double? discount;

  /// 备注（Go 端未返回该字段，故可空）。
  final String? note;
  final DateTime? expiresAt;

  /// 原样保存后端状态：active / used_up / expired / refreshed。
  final String status;

  const RedeemCode({
    required this.code,
    this.discount,
    this.note,
    this.expiresAt,
    required this.status,
  });

  /// 状态中文（兜底展示原值，避免未知状态被吞掉）。
  String get statusLabel => redeemStatusLabel(status);

  /// 折扣中文：`0.9` → `9折`、`0.85` → `8.5折`；无折扣返回 null。
  String? get discountLabel {
    final d = discount;
    if (d == null || d <= 0 || d >= 1) return null;
    final tenths = d * 10;
    final text = tenths == tenths.roundToDouble()
        ? tenths.round().toString()
        : tenths.toStringAsFixed(1);
    return '$text折';
  }

  /// 单条解析失败返回 null（调用方跳过坏行，不整包失败）。
  static RedeemCode? tryParse(Map<dynamic, dynamic> json) {
    final code = _toStr(json['code']);
    if (code.isEmpty) return null;
    final discountRaw = json['discount'];
    final noteRaw = json['note'];
    return RedeemCode(
      code: code,
      discount: discountRaw == null ? null : _toDouble(discountRaw),
      note: noteRaw is String && noteRaw.isNotEmpty ? noteRaw : null,
      expiresAt: _toDateTime(json['expires_at']),
      status: _toStr(json['status']),
    );
  }
}

/// 兑换码状态 → 中文。纯函数便于单测。
String redeemStatusLabel(String status) {
  switch (status) {
    case 'active':
      return '可用';
    case 'used_up':
      return '已用完';
    case 'expired':
      return '已过期';
    case 'refreshed':
      return '已刷新';
    default:
      return status.isEmpty ? '未知' : status;
  }
}

String _toStr(dynamic v) => v is String ? v : (v == null ? '' : '$v');

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double? _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

DateTime? _toDateTime(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v);
}

/// 邀请页解析入口：整包不是对象时抛统一解析错误。
InviteInfo parseInviteInfo(dynamic data) {
  if (data is! Map) {
    throw const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
  }
  return InviteInfo.fromJson(Map<String, dynamic>.from(data));
}
