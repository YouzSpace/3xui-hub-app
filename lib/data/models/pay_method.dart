import 'money.dart';

/// 支付方式（T6.1，`GET /api/payment/methods`）。
///
/// 逐字对齐 `server/internal/handler/api/payment.go:handlePaymentMethods`：
/// 只输出 `id` / `name` / `bank_code` 三个字段（api_key 等密钥不落响应）。
///
/// 注意：请求下单时这个 `id` 对应后端的 **`payment_config_id`** 字段，
/// 不是任务书里写的 `method_id`（以 handler 实现为准）。
class PayMethod {
  final int id;
  final String name;

  /// 网关标识（如 `epay` / `alipay`），可能为空串。
  final String bankCode;

  const PayMethod({
    required this.id,
    required this.name,
    required this.bankCode,
  });

  factory PayMethod.fromJson(Map<String, dynamic> json) {
    final id = jsonIntOrNull(json['id']);
    if (id == null) throwParseError();
    return PayMethod(
      id: id,
      name: jsonStr(json['name']),
      bankCode: jsonStr(json['bank_code']),
    );
  }

  static List<PayMethod> listFromJson(dynamic data) {
    if (data is! List) throwParseError();
    return [
      for (final item in data)
        if (item is Map<String, dynamic>)
          PayMethod.fromJson(item)
        else if (item is Map)
          PayMethod.fromJson(item.cast<String, dynamic>())
        else
          throwParseError(),
    ];
  }
}
