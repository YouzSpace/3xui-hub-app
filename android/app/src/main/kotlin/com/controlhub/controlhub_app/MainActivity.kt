package com.controlhub.controlhub_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // 分应用代理：向 Flutter 暴露已安装第三方应用列表（M4 T4.5）。
    private val installedAppsChannel = InstalledAppsChannel(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        installedAppsChannel.configure(flutterEngine)
    }
}
