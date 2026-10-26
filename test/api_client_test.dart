import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/network/api_client.dart';
import 'package:controlhub_app/core/network/api_exception.dart';

void main() {
  group('unwrapResponse', () {
    test('code==0 解包返回 data', () {
      final data = unwrapResponse({
        'code': 0,
        'msg': 'ok',
        'data': {'id': 12, 'email': 'a@b.com'},
      });
      expect(data, isA<Map>());
      expect((data as Map)['id'], 12);
    });

    test('code!=0 抛 ApiException 且带后端 msg', () {
      expect(
        () => unwrapResponse({'code': 401, 'msg': '登录已过期', 'data': null}),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 401)
            .having((e) => e.message, 'message', '登录已过期')),
      );
    });

    test('非标准结构原样返回（订阅纯文本正文）', () {
      expect(unwrapResponse('vless://abc'), 'vless://abc');
    });
  });

  group('mapDioError', () {
    DioException dioError(
      DioExceptionType type, {
      Response<dynamic>? response,
    }) =>
        DioException(
          requestOptions: RequestOptions(path: '/api/me'),
          type: type,
          response: response,
        );

    test('超时 → 网络错误文案 code=-1', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        final e = mapDioError(dioError(type));
        expect(e.code, ApiException.codeNetwork);
        expect(e.message, '网络连接失败，请检查网络');
      }
    });

    test('401 → 登录过期', () {
      final e = mapDioError(dioError(
        DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/api/me'),
          statusCode: 401,
        ),
      ));
      expect(e.code, 401);
      expect(e.message, '登录已过期');
    });

    test('429 → 优先用后端 msg', () {
      final e = mapDioError(dioError(
        DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/api/login'),
          statusCode: 429,
          data: {'code': 429, 'msg': '操作过于频繁，请稍后再试'},
        ),
      ));
      expect(e.code, 429);
      expect(e.message, '操作过于频繁，请稍后再试');
    });
  });
}
