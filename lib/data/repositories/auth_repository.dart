import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/token_store.dart';
import '../models/user_profile.dart';

/// 认证仓库（T2.2）：唯一能碰 ApiClient 的认证入口。
///
/// 铁律：登录成功写 TokenStore。退出登录的清理走 settings 的 LogoutService
/// （断 VPN → 清 token → 清缓存），不在这里做。
class AuthRepository {
  AuthRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// POST /api/login-email，返回 access_token（已写入 TokenStore）。
  Future<String> loginByEmail(String email, String password) =>
      _login('/api/login-email', {'email': email, 'password': password});

  /// POST /api/login（订阅 token 登录），返回 access_token（已写入 TokenStore）。
  Future<String> loginByToken(String token) =>
      _login('/api/login', {'token': token});

  /// GET /api/me（ApiClient 拦截器自动加 Bearer）。
  Future<UserProfile> fetchMe() async {
    final data = await _client.request('/api/me');
    if (data is! Map<String, dynamic>) {
      throw const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
    }
    return UserProfile.fromJson(data);
  }

  Future<String> _login(String path, Map<String, dynamic> body) async {
    final data = await _client.request(path, method: 'POST', data: body);
    if (data is! Map<String, dynamic>) {
      throw const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
    }
    final token = data['access_token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
    }
    await TokenStore.write(token);
    return token;
  }
}
