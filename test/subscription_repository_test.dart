import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/network/api_exception.dart';
import 'package:controlhub_app/data/repositories/subscription_repository.dart';

/// 走真实 HTTP 适配层之前的最小替身：直接给 Dio 换一个内存适配器，
/// 这样请求路径、响应头解析、错误映射都被真实执行（只有网络被替换）。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _text(String body, {Map<String, List<String>>? headers}) {
  return ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: ['text/plain; charset=UTF-8'],
      ...?headers,
    },
  );
}

const _vless1 =
    'vless://uuid@us.example.com:443?type=ws&security=tls#US-01';
const _vless2 =
    'vless://uuid@hk.example.com:8443?type=tcp#%E9%A6%99%E6%B8%AF';

SubscriptionRepository _repo(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://demo.example.com',
    responseType: ResponseType.plain,
  ));
  dio.httpClientAdapter = adapter;
  return SubscriptionRepository(dio: dio);
}

void main() {
  group('fetchRaw（T3.3）', () {
    test('成功：返回 base64 正文，请求路径带 token 且不带 Authorization', () async {
      final body = base64.encode(utf8.encode('$_vless1\n$_vless2'));
      final adapter = _FakeAdapter(
        (_) => _text(body, headers: {
          'x-ch-code': ['0'],
          'x-ch-msg': ['ok'],
        }),
      );
      final repo = _repo(adapter);

      expect(await repo.fetchRaw('sub-token'), body);
      expect(adapter.requests.single.path, '/api/sub/sub-token');
      expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
      // 纯文本响应：不能按 JSON 解析。
      expect(adapter.requests.single.responseType, ResponseType.plain);
    });

    test('X-CH-Code 非 0：抛 ApiException，message 取正文（剥 [404] 前缀）', () async {
      final adapter = _FakeAdapter(
        (_) => _text('[404] 用户不存在', headers: {
          'x-ch-code': ['404'],
          'x-ch-msg': ['用户不存在'],
        }),
      );
      await expectLater(
        _repo(adapter).fetchRaw('bad'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 404)
            .having((e) => e.message, 'message', '用户不存在')),
      );
    });

    test('流量用完（中文错误原样上屏）', () async {
      final adapter = _FakeAdapter(
        (_) => _text('[403] 流量已用完', headers: {'x-ch-code': ['403']}),
      );
      await expectLater(
        _repo(adapter).fetchRaw('t'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '流量已用完')),
      );
    });

    test('HTTP 头名大小写不敏感（Go 实际输出 X-Ch-Code）', () async {
      final adapter = _FakeAdapter(
        (_) => _text('[403] 账号已禁用', headers: {'X-Ch-Code': ['403']}),
      );
      await expectLater(
        _repo(adapter).fetchRaw('t'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 403)),
      );
    });

    test('缺 X-CH-Code 但正文为空 → 报内容为空', () async {
      final adapter = _FakeAdapter((_) => _text('   '));
      await expectLater(
        _repo(adapter).fetchRaw('t'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('订阅'))),
      );
    });

    test('空 token：直接报错，不发请求', () async {
      final adapter = _FakeAdapter((_) => _text('unused'));
      await expectLater(
        _repo(adapter).fetchRaw('  '),
        throwsA(isA<ApiException>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('fetchNodes（T3.3）', () {
    test('base64 订阅 → 节点列表', () async {
      final body = base64.encode(utf8.encode('$_vless1\n$_vless2'));
      final adapter = _FakeAdapter(
        (_) => _text(body, headers: {'x-ch-code': ['0']}),
      );
      final nodes = await _repo(adapter).fetchNodes('sub-token');

      expect(nodes, hasLength(2));
      expect(nodes[0].name, 'US-01');
      expect(nodes[0].host, 'us.example.com');
      expect(nodes[1].name, '香港');
      expect(nodes[1].port, 8443);
    });

    test('明文订阅也认（调试输出）', () async {
      final adapter = _FakeAdapter(
        (_) => _text('$_vless1\n\n$_vless2\n', headers: {'x-ch-code': ['0']}),
      );
      expect(await _repo(adapter).fetchNodes('t'), hasLength(2));
    });

    test('base64 解码失败 → 「订阅格式异常，请联系管理员」', () async {
      final garbage = '!!!${'x' * 80}';
      final adapter = _FakeAdapter(
        (_) => _text(garbage, headers: {'x-ch-code': ['0']}),
      );
      await expectLater(
        _repo(adapter).fetchNodes('t'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '订阅格式异常，请联系管理员')),
      );
    });

    test('合法 base64 但没有任何节点 → 空列表（不是异常）', () async {
      final body = base64.encode(utf8.encode('hello world\n# just a comment'));
      final adapter = _FakeAdapter(
        (_) => _text(body, headers: {'x-ch-code': ['0']}),
      );
      expect(await _repo(adapter).fetchNodes('t'), isEmpty);
    });

    test('业务错误优先于正文解析', () async {
      final adapter = _FakeAdapter(
        (_) => _text('[403] 流量已用完', headers: {'x-ch-code': ['403']}),
      );
      await expectLater(
        _repo(adapter).fetchNodes('t'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 403)),
      );
    });
  });
}
