import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/api_exception.dart';

/// 下载进度（T9.8）：已下载 / 总量 / 百分比，供 UI 直接展示。
class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});

  final int received;

  /// 总量；服务端没给 Content-Length 时为 0（未知）。
  final int total;

  /// 0~1；[total] 未知时为 0（UI 显示不确定进度条）。
  double get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;

  bool get known => total > 0;

  /// 百分比整数（0~100），未知时 0。
  int get percent => (fraction * 100).round();
}

/// 安装结果：UI 据此决定提示文案。
enum InstallStatus {
  /// 已拉起系统安装器（后续用户在安装器里可能取消，App 不追踪）。
  launched,

  /// 未授予「安装未知来源应用」权限（需要引导去系统设置）。
  permissionDenied,

  /// 拉起安装器失败（系统异常 / 无处理 apk 的应用）。
  launchFailed,

  /// 用户取消下载。
  cancelled,

  /// 下载失败、SHA256 不匹配、写入失败等（[InstallResult.message] 有文案）。
  failed,
}

class InstallResult {
  const InstallResult(this.status, [this.message]);

  final InstallStatus status;

  /// 可直接展示的中文提示（失败/被拒时必有）。
  final String? message;

  bool get ok => status == InstallStatus.launched;
}

typedef ProgressCallback = void Function(DownloadProgress progress);

/// 原生安装桥（`controlhub/app_install`，实现在 MainActivity.kt）。
///
/// 为什么在原生侧：`FileProvider` 的 authority 必须与 manifest 的 provider
/// 声明一致，`ACTION_VIEW` 又要拿 Activity 启动 —— 这两件事 Dart 侧做不了；
/// Dart 只负责下载、进度与 SHA256 校验。
class ApkInstallChannel {
  const ApkInstallChannel();

  static const MethodChannel _channel = MethodChannel('controlhub/app_install');

  /// 是否已允许「安装未知来源应用」。
  Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      // 通道不可用（非 Android / 老系统）：不在这里拦，安装时再兜底。
      return true;
    }
  }

  /// 跳「安装未知来源应用」系统设置页（用户拒绝后引导）。
  Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {
      // 打不开就只能让用户自己去设置里找，UI 已给出提示。
    }
  }

  /// 拉起系统安装器；返回错误文案（null = 已成功拉起）。
  Future<String?> install(String filePath) async {
    try {
      final err = await _channel.invokeMethod<String>('install', {
        'path': filePath,
      });
      return (err == null || err.isEmpty) ? null : err;
    } on PlatformException catch (e) {
      return e.message ?? '无法拉起系统安装器';
    } catch (_) {
      return '无法拉起系统安装器';
    }
  }
}

/// 文件与哈希操作的可注入边界（单测换内存实现，不碰真磁盘）。
abstract interface class ApkStorage {
  /// 本次下载的目标文件（位于临时目录）。
  Future<File> targetFile(String name);

  /// 打开写入流（真实实现写磁盘；单测写内存）。
  Future<IOSink> openWrite(File file);

  /// 文件 SHA256（小写十六进制）。
  Future<String> sha256Of(File file);

  Future<bool> exists(File file);

  Future<void> delete(File file);
}

class DefaultApkStorage implements ApkStorage {
  const DefaultApkStorage();

  @override
  Future<File> targetFile(String name) async {
    final dir = await getTemporaryDirectory();
    // 独立文件名：上一次残留的半包不会被当成本次产物。
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return File('${dir.path}${Platform.pathSeparator}$name-$stamp.apk');
  }

  @override
  Future<IOSink> openWrite(File file) async => file.openWrite();

  @override
  Future<String> sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  @override
  Future<bool> exists(File file) => file.exists();

  @override
  Future<void> delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删不掉不影响流程（临时目录由系统回收）。
    }
  }
}

/// 下载 → 校验 → 拉起系统安装器（T9.8）。
///
/// 规则：失败/取消一律清理临时文件；SHA256 不一致删文件并提示重试。
/// 已校验通过但没装成的包（例如未知来源权限被拒）内存留一个引用，
/// 用户去设置授权后点 [重试] 不会重新下载几十 MB。
class ApkInstaller {
  ApkInstaller({
    Dio? dio,
    ApkStorage? storage,
    ApkInstallChannel? channel,
    this.chunkBytes = defaultChunkBytes,
  })  : _dio = dio ?? buildDownloadDio(),
        _storage = storage ?? const DefaultApkStorage(),
        _channel = channel ?? const ApkInstallChannel();

  /// 进度回调节流：每累计这么多字节回调一次，避免逐块 setState。
  static const int defaultChunkBytes = 200 * 1024;

  final Dio _dio;
  final ApkStorage _storage;
  final ApkInstallChannel _channel;
  final int chunkBytes;

  File? _verifiedFile;
  String? _verifiedSha;

  /// 已校验通过的临时包（同一次弹窗内重试时复用）。
  File? get verifiedFile => _verifiedFile;

  /// 是否已允许安装未知来源应用。
  Future<bool> canInstall() => _channel.canInstall();

  /// 跳系统设置授权未知来源安装。
  Future<void> openInstallSettings() => _channel.openInstallSettings();

  Future<InstallResult> downloadAndInstall({
    required String url,
    required String? expectedSha256,
    ProgressCallback? onProgress,
    void Function()? onVerifying,
    CancelToken? cancelToken,
  }) async {
    final expected = normalizeSha(expectedSha256);

    // 1) 复用上一次已校验的文件（权限被拒后授权重试的常见路径）。
    final cached = _verifiedFile;
    if (cached != null &&
        _verifiedSha == expected &&
        await _storage.exists(cached)) {
      return _install(cached);
    }

    // 2) 下载。
    final File file;
    try {
      file = await _storage.targetFile('controlhub-update');
    } catch (e) {
      return InstallResult(InstallStatus.failed, _message(e));
    }

    try {
      final completed = await _download(
        url: url,
        file: file,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (!completed) {
        await _storage.delete(file);
        return const InstallResult(InstallStatus.cancelled);
      }
    } catch (e) {
      await _storage.delete(file);
      // CancelToken 取消在 dio 里是 DioException(cancel)，要映射成 cancelled，
      // 否则可选更新会停在「下载失败」而不是回到提示态。
      if (_isCancel(e)) return const InstallResult(InstallStatus.cancelled);
      return InstallResult(InstallStatus.failed, _message(e));
    }

    onVerifying?.call();

    // 3) SHA256 校验（接口没给 sha256 时跳过：只能相信下载完整性）。
    if (expected != null) {
      final String actual;
      try {
        actual = normalizeSha(await _storage.sha256Of(file)) ?? '';
      } catch (e) {
        await _storage.delete(file);
        return InstallResult(InstallStatus.failed, _message(e));
      }
      if (actual != expected) {
        await _storage.delete(file);
        return const InstallResult(
          InstallStatus.failed,
          '安装包校验失败，请重试',
        );
      }
    }
    _verifiedFile = file;
    _verifiedSha = expected;

    return _install(file);
  }

  /// 授权 → 拉起安装器；失败时按需清理。
  Future<InstallResult> _install(File file) async {
    if (!await _channel.canInstall()) {
      // 保留文件：用户去系统设置授权后点重试，直接走 _install。
      return const InstallResult(
        InstallStatus.permissionDenied,
        '需要允许安装未知来源应用',
      );
    }
    final error = await _channel.install(file.path);
    if (error != null) {
      await _storage.delete(file);
      _verifiedFile = null;
      _verifiedSha = null;
      return InstallResult(InstallStatus.launchFailed, error);
    }
    // 拉起安装器后文件必须保留：系统安装器在另一个进程里读它。
    return const InstallResult(InstallStatus.launched);
  }

  /// 返回 true = 下载完整；false = 被取消。
  Future<bool> _download({
    required String url,
    required File file,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        // 安装包几十 MB：不限制「整包耗时」，只限制收到响应头的等待。
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        validateStatus: (s) => s != null && s >= 200 && s < 300,
      ),
    );

    final total = _contentLength(response);
    final sink = await _storage.openWrite(file);
    var received = 0;
    var lastReported = 0;
    var cancelled = false;
    try {
      final stream = response.data!.stream;
      await for (final chunk in stream) {
        if (cancelToken?.isCancelled ?? false) {
          cancelled = true;
          break;
        }
        sink.add(chunk);
        received += chunk.length;
        if (received - lastReported >= chunkBytes) {
          lastReported = received;
          onProgress?.call(DownloadProgress(received: received, total: total));
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    onProgress?.call(DownloadProgress(received: received, total: total));
    if (cancelled) return false;
    // 服务端给了总长但没收够：不是完整安装包，交给上层按失败处理。
    if (total > 0 && received != total) {
      throw const ApiException(ApiException.codeNetwork, '下载不完整，请重试');
    }
    return true;
  }

  static bool _isCancel(Object e) =>
      e is DioException && e.type == DioExceptionType.cancel;

  int _contentLength(Response<ResponseBody> response) {
    final raw = response.headers.value(Headers.contentLengthHeader);
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// 统一小写十六进制；容忍 `sha256:` 前缀与空白；空值返回 null。
  static String? normalizeSha(String? value) {
    if (value == null) return null;
    var v = value.trim().toLowerCase();
    if (v.startsWith('sha256:')) v = v.substring(7).trim();
    return v.isEmpty ? null : v;
  }

  static String _message(Object e) {
    if (e is ApiException) return e.message;
    if (e is DioException) {
      if (e.type == DioExceptionType.cancel) return '下载已取消';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        return '下载失败，请检查网络';
      }
      final status = e.response?.statusCode;
      if (status != null && status >= 400) return '下载失败（HTTP $status），请重试';
    }
    if (e is FileSystemException) return '写入文件失败，请检查存储空间';
    return '下载失败，请重试';
  }
}

/// 下载专用 Dio：不走 ApiClient 的业务拦截器 —— 安装包在 CDN/对象存储上，
/// 不需要 Bearer，也不会是 `{code,msg,data}` 结构。
Dio buildDownloadDio() => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {'Accept': 'application/vnd.android.package-archive, */*'},
    ));
