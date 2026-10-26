import 'money.dart';

/// 订单（T6.1，`GET /api/payment/orders`）。
///
/// 逐字对齐 `server/internal/handler/api/payment.go:handlePaymentOrders`：
/// 最近 20 条，`{order_no, plan_id, plan_name, order_type, amount, status, paid_at, created_at}`。
///
/// 三处可空是后端真实行为，不能按 0/空串处理：
/// - `plan_id`：代理订单没有套餐 → null；
/// - `paid_at`：未支付 → null；
/// - `plan_name`：后端已兜底成 `-` 或 `代理 · xxx`，这里按空串兜。
class Order {
  final String orderNo;

  /// 套餐 id；代理订单为 null。
  final int? planId;

  /// 套餐名（后端已兜底，代理订单形如 `代理 · 名称`）。
  final String planName;

  /// `plan`（套餐单）/ `reset`（重置流量）/ 代理相关类型。
  final String orderType;

  /// 实付金额（元，已折后）。
  final Money amount;

  final String status;

  /// 支付时间；未支付为 null。
  final DateTime? paidAt;

  final DateTime? createdAt;

  const Order({
    required this.orderNo,
    required this.planId,
    required this.planName,
    required this.orderType,
    required this.amount,
    required this.status,
    required this.paidAt,
    required this.createdAt,
  });

  bool get isPaid => status == OrderStatus.paid;

  /// 只有待支付单可以「继续支付」。
  bool get canRetry => status == OrderStatus.pending;

  /// 状态徽章文案。
  String get statusLabel => OrderStatus.label(status);

  factory Order.fromJson(Map<String, dynamic> json) {
    final orderNo = jsonStr(json['order_no']);
    if (orderNo.isEmpty) throwParseError();
    return Order(
      orderNo: orderNo,
      planId: jsonIntOrNull(json['plan_id']),
      planName: jsonStr(json['plan_name']),
      orderType: jsonStr(json['order_type']),
      amount: Money.parse(json['amount']),
      status: jsonStr(json['status']),
      paidAt: jsonDate(json['paid_at']),
      createdAt: jsonDate(json['created_at']),
    );
  }

  static List<Order> listFromJson(dynamic data) {
    if (data is! List) throwParseError();
    return [
      for (final item in data)
        if (item is Map<String, dynamic>)
          Order.fromJson(item)
        else if (item is Map)
          Order.fromJson(item.cast<String, dynamic>())
        else
          throwParseError(),
    ];
  }
}

/// 订单状态常量（system-design §7：判断到账**只认 `paid`**）。
abstract class OrderStatus {
  static const pending = 'pending';
  static const paid = 'paid';
  static const expired = 'expired';
  static const cancelled = 'cancelled';

  /// 状态徽章文案（T6.6：待支付/已支付/已关闭）。
  static String label(String status) {
    switch (status) {
      case paid:
        return '已支付';
      case pending:
        return '待支付';
      case expired:
        return '已关闭';
      case cancelled:
        return '已取消';
      default:
        return status.isEmpty ? '未知' : status;
    }
  }
}

/// 续付结果（T6.2，`POST /api/payment/retry`）。
///
/// 后端成功只回 `{order_no, pay_url}`（任务书写「同 create」是简化说法，
/// 以 handler 为准 —— retry 不带 amount/status）。
class RetryPayResult {
  final String orderNo;
  final String payUrl;

  const RetryPayResult({required this.orderNo, required this.payUrl});

  factory RetryPayResult.fromJson(Map<String, dynamic> json) {
    final orderNo = jsonStr(json['order_no']);
    final payUrl = jsonStr(json['pay_url']);
    if (orderNo.isEmpty || payUrl.isEmpty) throwParseError();
    return RetryPayResult(orderNo: orderNo, payUrl: payUrl);
  }
}

/// 下单结果（T6.2，`POST /api/payment/create`）。
///
/// `{order_no, amount, status, pay_url}`；`amount` 是折后实付（元）。
/// 免费套餐后端直接返回 `status=paid` 且 `pay_url=null`。
class CreateOrderResult {
  final String orderNo;
  final Money amount;
  final String status;

  /// 支付页地址；免费/已支付订单为 null。
  final String? payUrl;

  const CreateOrderResult({
    required this.orderNo,
    required this.amount,
    required this.status,
    required this.payUrl,
  });

  /// 免费套餐 / 复用已支付单时后端直接给 paid。
  bool get isPaid => status == OrderStatus.paid;

  factory CreateOrderResult.fromJson(Map<String, dynamic> json) {
    final orderNo = jsonStr(json['order_no']);
    if (orderNo.isEmpty) throwParseError();
    final rawUrl = json['pay_url'];
    final url = rawUrl is String && rawUrl.isNotEmpty ? rawUrl : null;
    return CreateOrderResult(
      orderNo: orderNo,
      amount: Money.parse(json['amount']),
      status: jsonStr(json['status']),
      payUrl: url,
    );
  }
}

/// 支付状态查询结果（`GET /api/payment/status?order_no=`）。
///
/// `{order_no, status, amount, paid_at}`；`paid_at` 未支付时为 null。
class OrderStatusResult {
  final String orderNo;
  final String status;
  final Money amount;
  final DateTime? paidAt;

  const OrderStatusResult({
    required this.orderNo,
    required this.status,
    required this.amount,
    required this.paidAt,
  });

  bool get isPaid => status == OrderStatus.paid;

  /// 订单已关闭（过期/取消）—— 不能再续付，只能重新下单。
  bool get isClosed =>
      status == OrderStatus.expired || status == OrderStatus.cancelled;

  factory OrderStatusResult.fromJson(Map<String, dynamic> json) {
    final orderNo = jsonStr(json['order_no']);
    if (orderNo.isEmpty) throwParseError();
    return OrderStatusResult(
      orderNo: orderNo,
      status: jsonStr(json['status']),
      amount: Money.parse(json['amount']),
      paidAt: jsonDate(json['paid_at']),
    );
  }
}

/// 优惠码校验结果（T6.2，`POST /api/discount/check`）。
///
/// **契约分歧（关键，已按真实实现处理）**：Web 前端 `api/user.js` 读的是
/// `{usable, discount, final_amount, note, message}`，任务书只写了「折扣结果」，
/// 而 Go handler `user_extras.go:handleDiscountCheck` 目前只回 `{valid, code}`
/// 且没读 `plan_id`（PHP 版 `DiscountController::check` 才是完整结构）。
///
/// App 侧按 PHP/Web 的**完整结构**解析，同时兼容 Go 的精简结构：
/// - 有 `final_amount` → 用后端算好的折后价（口径永远一致）；
/// - 只有 `valid=true` → 折后价未知（[hasFinalAmount] == false），UI 不明示
///   「已优惠」，真实金额以 `createOrder` 返回的 `amount` 为准（下单仍会带码）。
class DiscountResult {
  /// 码是否可用。
  final bool usable;

  /// 折扣率（0.90 = 9 折）；后端没给则为 null。
  final double? rate;

  /// 折后价（元）；后端没给则为 null。
  final Money? finalAmount;

  /// 服务端一句话说明（可直接展示）。
  final String message;

  /// 码的自定义说明（后端 `note`）。
  final String note;

  const DiscountResult({
    required this.usable,
    required this.rate,
    required this.finalAmount,
    required this.message,
    required this.note,
  });

  /// 失败结果（本地构造，如网络异常）。
  factory DiscountResult.invalid(String message) => DiscountResult(
        usable: false,
        rate: null,
        finalAmount: null,
        message: message,
        note: '',
      );

  /// 是否拿到了确定的折后价（决定 UI 能否展示划线原价）。
  bool get hasFinalAmount => usable && finalAmount != null;

  factory DiscountResult.fromJson(Map<String, dynamic> json) {
    // 两套键名取并集：usable(PHP/Web) 优先，valid(Go) 兜底。
    final rawUsable = json['usable'] ?? json['valid'];
    final usable = rawUsable == true;
    final rawRate = json['discount'];
    double? rate;
    if (rawRate is num) {
      rate = rawRate.toDouble();
    } else if (rawRate is String) {
      rate = double.tryParse(rawRate.trim());
    }
    final rawFinal = json['final_amount'];
    final finalAmount = rawFinal == null ? null : Money.parse(rawFinal);
    return DiscountResult(
      usable: usable,
      rate: rate,
      finalAmount: finalAmount,
      message: jsonStr(json['message']),
      note: jsonStr(json['note']),
    );
  }
}
