package com.controlhub.controlhub_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 主 Activity + APK 安装桥（M9B / T9.8）。
 *
 * 安装 APK 必须走原生：FileProvider 的 authority、unknown-sources 授权页、
 * ACTION_VIEW 都要 Activity/Context，Dart 侧拿不到。
 * 通道名与 `lib/features/update/apk_installer.dart` 的 ApkInstallChannel 对应。
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "controlhub/app_install"
        const val APK_MIME = "application/vnd.android.package-archive"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canInstallPackages())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        result.success(installApk(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Android 8.0+ 才需要「安装未知来源应用」授权；更早的版本恒为 true。 */
    private fun canInstallPackages(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (_: ActivityNotFoundException) {
            // 个别 ROM 没有这个页面：跳到应用详情页兜底。
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.parse("package:$packageName"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (_: Exception) {
                // 两个都打不开就放弃，Dart 侧已提示用户手动开启。
            }
        }
    }

    /**
     * 用 FileProvider 把临时目录里的 APK 交给系统安装器。
     * 返回 null = 已成功拉起；否则返回可展示给用户的错误文案。
     */
    private fun installApk(path: String?): String? {
        if (path.isNullOrEmpty()) return "安装包路径无效"
        val file = File(path)
        if (!file.exists()) return "安装包不存在，请重新下载"
        if (!canInstallPackages()) return "需要允许安装未知来源应用"

        return try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            null
        } catch (_: ActivityNotFoundException) {
            "无法拉起系统安装器"
        } catch (_: IllegalArgumentException) {
            // 文件不在 FileProvider 声明的路径里（不该发生：下载固定落 cacheDir）。
            "安装包路径不受支持"
        } catch (e: Exception) {
            "拉起安装器失败"
        }
    }
}
