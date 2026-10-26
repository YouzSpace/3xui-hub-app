import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/plan.dart';

/// 套餐仓库（T6.2）：唯一能碰 `/api/plans` 的入口。
///
/// 铁律：Widget 里不出现 dio；网络错误已由 ApiClient 统一转 ApiException。
class PlanRepository {
  PlanRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// GET /api/plans → 可购买套餐列表（后端已过滤 is_active）。
  Future<List<Plan>> fetchPlans() async {
    final data = await _client.request('/api/plans');
    try {
      return Plan.listFromJson(data);
    } on ApiException {
      rethrow;
    } catch (_) {
      // 结构异常统一收敛成可展示文案（不把 Dart 异常泄露到 UI）。
      throw const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
    }
  }
}
