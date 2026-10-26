import 'package:dio/dio.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../vpn/subscription_parser.dart';
import '../models/node.dart';

/// 订阅仓库（T3.3）：唯一能碰 `GET /api/sub/{token}` 的入口。
///
/// **刻意不用 [ApiClient]**：`ApiClient` 的拦截器会把响应体当 `{code,msg,data}`
/// 解包，而订阅返回的是**纯文本**（base64 或明文分享链接）。这里用独立 Dio +
/// `ResponseType.plain`，错误码走响应头 `X-CH-Code`（HTTP 状态恒为 200，
/// 见 server/internal/subscription/handler.go）。
class SubscriptionRepository {
  SubscriptionRepository({Dio? dio}) : _dio = dio ?? _buildDio();

  final Dio _dio;

  /// 订阅接口不需要 Bearer（token 即凭证），也绝不能带 Authorization
  /// —— 带错 token 反而会被服务端当成别的凭证处理。
  static Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConfig.base,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      // 纯文本正文：不走 JSON 解码，也不会被统一解包逻辑影响。
      responseType: ResponseType.plain,
      headers: const {'Accept': 'text/plain'},
    ));
    // 全局只有 ApiClient 加 Bearer；这里另建实例，天然不带。
    return dio;
  }

  /// GET /api/sub/{token} → 正文文本（已按需要做过 base64 解码前的原样文本）。
  ///
  /// `X-CH-Code != 0` 时抛 [ApiException]，message 取后端正文
  /// （Go 输出形如 `[404] 用户不存在`，这里剥掉 `[...]` 前缀只留可展示文案）。
  Future<String> fetchRaw(String token) async {
    final sub = token.trim();
    if (sub.isEmpty) {
      throw const ApiException(401, '缺少订阅凭证，请重新登录');
    }

    final Response<dynamic> res;
    try {
      res = await _dio.get<dynamic>(
        '/api/sub/${Uri.encodeComponent(sub)}',
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }

    final body = res.data is String
        ? res.data as String
        : (res.data?.toString() ?? '');
    final code = _readHeaderCode(res.headers, 'x-ch-code');
    if (code != null && code != 0) {
      throw ApiException(code, _errorMessage(body, res.headers));
    }
    // 没有 X-CH-Code 头的极端情况（前置代理/缓存剥头）：正文不像订阅就当异常。
    if (body.trim().isEmpty) {
      throw const ApiException(ApiException.codeParse, '订阅内容为空，请联系管理员');
    }
    return body;
  }

  /// GET /api/sub/{token} → 节点列表。
  ///
  /// base64 解码失败 → 「订阅格式异常，请联系管理员」；
  /// 解码成功但没有节点 → 空列表（由 UI 展示「当前没有可用节点」）。
  Future<List<Node>> fetchNodes(String token) async {
    final body = await fetchRaw(token);
    final result = SubscriptionParser.parseDetailed(body);
    if (result.base64DecodeFailed) {
      throw const ApiException(ApiException.codeParse, '订阅格式异常，请联系管理员');
    }
    return result.nodes;
  }

  /// 读取响应头里的业务码。HTTP 头名大小写不敏感（Go 实际输出 `X-Ch-Code`），
  /// Dio 的 [Headers] 本身就是小写归一化的，这里再兜一层以防自定义 Dio 实现。
  static int? _readHeaderCode(Headers headers, String name) {
    final raw = headers.value(name) ?? headers.value(name.toLowerCase());
    if (raw == null) return null;
    return int.tryParse(raw.trim());
  }

  /// 错误文案：优先正文（剥掉 `[404] ` 前缀），其次 `X-CH-Msg` 头，最后兜底。
  static String _errorMessage(String body, Headers headers) {
    final text = body.trim();
    if (text.isNotEmpty) {
      final prefixed = RegExp(r'^\[\d+\]\s*').firstMatch(text);
      final stripped =
          prefixed == null ? text : text.substring(prefixed.end).trim();
      if (stripped.isNotEmpty) return stripped;
    }
    final headerMsg = headers.value('x-ch-msg')?.trim();
    if (headerMsg != null && headerMsg.isNotEmpty && headerMsg != 'ok') {
      return headerMsg;
    }
    return '订阅获取失败，请稍后重试';
  }

  /// DioException → 可展示的 [ApiException]（与 ApiClient 的口径保持一致）。
  static ApiException _mapError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) return const ApiException(401, '登录已过期');
    if (status == 404) return const ApiException(404, '订阅地址不存在，请联系管理员');
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return const ApiException(ApiException.codeNetwork, '网络连接失败，请检查网络');
      default:
        return const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
    }
  }
}
