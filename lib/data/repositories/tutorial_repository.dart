import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/tutorial.dart';

/// 教程仓库（T7.2 / T7.3）。
class TutorialRepository {
  TutorialRepository({ApiClient? client})
      : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// GET /api/tutorials（公开接口，无需 Bearer）。
  Future<List<Tutorial>> fetchAll() async {
    final data = await _client.request('/api/tutorials');
    return Tutorial.listFromJson(data);
  }

  /// GET /api/tutorials/{id}。
  ///
  /// 后端对不存在/未启用返回 HTTP 404 + `{code:404,msg:"Not found"}`，
  /// 拦截器按状态码映射成统一网络错误，因此这里只校验结构。
  Future<Tutorial> fetchById(int id) async {
    final data = await _client.request('/api/tutorials/$id');
    if (data is! Map) {
      throw const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
    }
    return Tutorial.fromJson(Map<String, dynamic>.from(data));
  }
}
