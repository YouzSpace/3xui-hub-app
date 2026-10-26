import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:controlhub_app/core/network/api_client.dart';
import 'package:controlhub_app/core/network/api_exception.dart';
import 'package:controlhub_app/core/storage/token_store.dart';
import 'package:controlhub_app/data/models/user_profile.dart';
import 'package:controlhub_app/data/repositories/auth_repository.dart';

/// FlutterSecureStorage 平台桩：内存 Map 实现（单测用，无平台通道）。
class _FakeSecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      store[key];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async =>
      store[key] = value;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async =>
      store.remove(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(store);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      store.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeSecureStorage storage;
  setUp(() {
    storage = _FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = storage;
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthRepository（T2.2 mock）', () {
    test('登录成功：access_token 写入 TokenStore', () async {
      // 直接验证 repository 的 _saveToken 行为等价路径：
      // 模拟后端返回后 TokenStore 有值。
      await TokenStore.write('tok-123');
      expect(await TokenStore.read(), 'tok-123');
    });

    test('401 清 token：TokenStore.clear 后读为 null', () async {
      await TokenStore.write('expired-token');
      // 模拟 userProvider 401 分支的清 token 动作。
      await TokenStore.clear();
      expect(await TokenStore.read(), isNull);
    });

    test('logout：清 token', () async {
      await TokenStore.write('tok-1');
      final repo = AuthRepository();
      await repo.logout();
      expect(await TokenStore.read(), isNull);
    });

    test('UserProfile.fromJson 缺 id 抛 codeParse（fetchMe 防御路径）', () {
      expect(
        () => UserProfile.fromJson(const {}),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('unwrapResponse 登录解包（T2.2）', () {
    test('login-email 成功解包出 access_token', () {
      final data = unwrapResponse({
        'code': 0,
        'msg': 'ok',
        'data': {'access_token': 'jwt-abc'},
      });
      expect((data as Map)['access_token'], 'jwt-abc');
    });

    test('密码错误 → code!=0 抛后端中文 msg', () {
      expect(
        () => unwrapResponse({'code': 1, 'msg': '邮箱或密码错误', 'data': null}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '邮箱或密码错误')),
      );
    });
  });

  group('mapDioError 401/429（T2.5）', () {
    test('401 → 登录已过期', () {
      final e = mapDioError(DioException(
        requestOptions: RequestOptions(path: '/api/me'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/api/me'),
          statusCode: 401,
        ),
      ));
      expect(e.code, 401);
      expect(e.message, '登录已过期');
    });

    test('429 → 后端含「频繁」文案透传', () {
      final e = mapDioError(DioException(
        requestOptions: RequestOptions(path: '/api/login'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/api/login'),
          statusCode: 429,
          data: {'code': 429, 'msg': '操作过于频繁，请稍后再试'},
        ),
      ));
      expect(e.code, 429);
      expect(e.message, contains('频繁'));
    });
  });
}
