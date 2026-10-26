import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/money.dart';
import '../models/order.dart';
import '../models/pay_method.dart';

/// 支付/订单仓库（T6.2）：唯一能碰 `/api/payment/**` 与 `/api/discount/check` 的入口。
///
/// 请求体字段以 Go handler 为准（`payment.go` / `user_extras.go`）：
/// - 下单用 **`payment_config_id`**，不是 `method_id`；
/// - 优惠码校验后端当前没读 `plan_id`，但 PHP/Web 都传，照样传（向后兼容）。
class OrderRepository {
  OrderRepository({ApiClient? client})
      : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// GET /api/payment/methods → 可用支付方式（后端已过滤 enabled）。
  Future<List<PayMethod>> fetchMethods() async {
    final data = await _client.request('/api/payment/methods');
    return _guard(() => PayMethod.listFromJson(data));
  }

  /// POST /api/payment/create → 建单。
  ///
  /// [methodId] 对应后端 `payment_config_id`；不传则用站点默认通道。
  Future<CreateOrderResult> createOrder({
    required int planId,
    int? methodId,
    String? discountCode,
  }) async {
    final body = <String, dynamic>{'plan_id': planId};
    if (methodId != null && methodId > 0) {
      body['payment_config_id'] = methodId;
    }
    final code = discountCode?.trim();
    if (code != null && code.isNotEmpty) {
      body['discount_code'] = code;
    }
    final data = await _client.request(
      '/api/payment/create',
      method: 'POST',
      data: body,
    );
    return _guard(() => CreateOrderResult.fromJson(_asMap(data)));
  }

  /// GET /api/payment/status?order_no= → 支付状态（轮询用）。
  Future<OrderStatusResult> queryStatus(String orderNo) async {
    final data = await _client.request(
      '/api/payment/status',
      query: {'order_no': orderNo},
    );
    return _guard(() => OrderStatusResult.fromJson(_asMap(data)));
  }

  /// GET /api/payment/orders → 最近 20 笔订单。
  Future<List<Order>> fetchOrders() async {
    final data = await _client.request('/api/payment/orders');
    return _guard(() => Order.listFromJson(data));
  }

  /// POST /api/payment/retry → 续付拿到新的 pay_url。
  ///
  /// 后端在「网关判重」时返回 code 410「支付链接已失效，请返回商城重新下单」，
  /// 已由 ApiClient 转成 ApiException 抛出，调用方按 message 展示即可。
  Future<RetryPayResult> retryPay(String orderNo) async {
    final data = await _client.request(
      '/api/payment/retry',
      method: 'POST',
      data: {'order_no': orderNo},
    );
    return _guard(() => RetryPayResult.fromJson(_asMap(data)));
  }

  /// POST /api/discount/check → 校验优惠码（不占用次数）。
  ///
  /// 注意：校验失败时后端可能**抛 ApiException**（Go: code 400「优惠码无效或不可用」），
  /// 也可能**正常返回** `{usable:false, message}`（PHP）。两种都算「不可用」，
  /// 由 [checkDiscount] 归一成 [DiscountResult] 返回，调用方不用 try/catch。
  Future<DiscountResult> checkDiscount(String code, int planId) async {
    try {
      final data = await _client.request(
        '/api/discount/check',
        method: 'POST',
        data: {'code': code.trim(), 'plan_id': planId},
      );
      return DiscountResult.fromJson(_asMap(data));
    } on ApiException catch (e) {
      // 429 限流要原样上抛（UI 需要走「频繁输码」的提示分支）。
      if (e.code == 429) rethrow;
      return DiscountResult.invalid(e.message);
    }
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    throwParseError();
  }

  /// 把解析期的任意异常收敛成 ApiException(codeParse)，避免 Dart 原生异常冒到 UI。
  static T _guard<T>(T Function() parse) {
    try {
      return parse();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
    }
  }
}
