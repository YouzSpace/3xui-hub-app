import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../storage/token_store.dart';
import 'api_exception.dart';

/// 解包 `{code,msg,data}`：`code == 0` 返回 `data`，否则抛 ApiException。
///
/// 非标准结构（如纯文本订阅正文）原样返回，交给订阅仓库处理。
/// 抽成纯函数便于单测。
dynamic unwrapResponse(dynamic data) {
  if (data is Map && data.containsKey('code')) {
    final code = data['code'];
    if (code == 0) return data['data'];
    final codeInt = code is int ? code : ApiException.codeParse;
    final msg = data['msg'];
    throw ApiException(codeInt, msg is String ? msg : '请求失败');
  }
  return data;
}

/// 把 DioException 映射成可展示的 ApiException（system-design §7）。
///
/// 抽成纯函数便于单测。
ApiException mapDioError(DioException e) {
  final status = e.response?.statusCode;
  if (status == 401) return const ApiException(401, '登录已过期');
  if (status == 429) {
    final data = e.response?.data;
    final msg = (data is Map && data['msg'] is String) ? data['msg'] as String : null;
    return ApiException(429, msg ?? '操作过于频繁，请稍后再试');
  }
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

/// 统一 API 客户端（T1.4）。
///
/// 铁律：Widget 里不出现 dio；只有 repository 用 [ApiClient.dio] 发请求。
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  late final Dio dio = _build();

  Dio _build() {
    final d = Dio(BaseOptions(
      baseUrl: ApiConfig.base,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      contentType: 'application/json',
    ));

    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // 有 token 时加 Bearer。
        final token = await TokenStore.read();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        try {
          response.data = unwrapResponse(response.data);
          handler.next(response);
        } on ApiException catch (e) {
          handler.reject(DioException(
            requestOptions: response.requestOptions,
            response: response,
            error: e,
            type: DioExceptionType.badResponse,
          ));
        }
      },
      onError: (error, handler) {
        // 已是业务错误（onResponse 抛的）就不再二次映射。
        if (error.error is ApiException) {
          handler.next(error);
          return;
        }
        final mapped = mapDioError(error);
        handler.reject(DioException(
          requestOptions: error.requestOptions,
          response: error.response,
          error: mapped,
          type: error.type,
        ));
      },
    ));
    return d;
  }

  /// 发起请求并把 DioException 统一转成 ApiException（repository 用）。
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method),
      );
      return res.data;
    } on DioException catch (e) {
      if (e.error is ApiException) throw e.error as ApiException;
      throw mapDioError(e);
    }
  }
}
