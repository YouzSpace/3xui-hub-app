package com.controlhub.controlhub_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 分应用代理数据通道（M4 T4.5）：给 Flutter 提供「已安装第三方应用」列表。
 *
 * 只返回有启动器入口的应用（即用户能打开的应用），按名称排序；
 * 非 Android 平台（debug/profile 下运行在非 Android 环境）不会注册。
 */
class InstalledAppsChannel(private val context: Context) {

    companion object {
        private const val CHANNEL = "controlhub/installed_apps"
    }

    fun configure(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApps" -> result.success(installedApps())
                    else -> result.notImplemented()
                }
            }
    }

    private fun installedApps(): List<Map<String, String>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val launcherActivities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, android.content.pm.PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
        val self = context.packageName
        return launcherActivities
            .mapNotNull { it.activityInfo?.applicationInfo }
            .filter { it.packageName != self }
            .distinctBy { it.packageName }
            .mapNotNull { appInfo ->
                val label = pm.getApplicationLabel(appInfo)?.toString()
                if (label.isNullOrBlank()) null else mapOf(
                    "packageName" to appInfo.packageName,
                    "appName" to label,
                )
            }
            .sortedBy { it["appName"] ?: "" }
    }
}
