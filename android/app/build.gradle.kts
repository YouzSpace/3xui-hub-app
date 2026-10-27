import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 包名：客户改品牌时只改这一处（namespace 与 applicationId 共用）。
val appId = "com.controlhub.controlhub_app"

// 签名配置：本地读 key.properties，CI 读环境变量（keystore 由 secret 解码后落盘）。
val keystoreProperties = Properties().apply {
    val f = file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {
    namespace = appId
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 包名见顶部 appId，客户改品牌只改那一处。
        applicationId = appId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 固定 23：flutter_vless 及项目契约要求（Android 6.0 起）。
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val f = System.getenv("KEYSTORE_PATH") ?: keystoreProperties["storeFile"] as? String
            if (!f.isNullOrBlank()) {
                storeFile = file(f)
                storePassword = System.getenv("KEYSTORE_PASSWORD") ?: keystoreProperties["storePassword"] as? String
                keyAlias = System.getenv("KEY_ALIAS") ?: keystoreProperties["keyAlias"] as? String
                keyPassword = System.getenv("KEY_PASSWORD") ?: keystoreProperties["keyPassword"] as? String
            }
        }
    }

    buildTypes {
        release {
            // 有正式签名配置（key.properties / CI 环境变量）用正式签名，否则退回 debug（本地开发）。
            signingConfig = if (signingConfigs.getByName("release").storeFile != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    // flutter_vless 的 libxray.so 需要解压加载（T1.1 硬要求，漏了连接时会崩）。
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

// 只对 release 排除非 arm64 的 native 库（APK 从 83MB 降到 32MB）。
// debug 保留全架构：本地模拟器是 x86_64，排除会连不了 VPN。
// AAR 依赖的 prebuilt .so 不受 ndk.abiFilters 控制，只能用 packaging excludes。
// 客户要兼容老 32 位手机（armeabi-v7a）时删掉这段。
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.addAll(
            listOf("lib/armeabi-v7a/**", "lib/x86_64/**", "lib/x86/**")
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// M9B / T9.8：MainActivity 里用 androidx.core.content.FileProvider 安装 APK。
// Flutter 模板不带这份显式依赖，补上（版本交给各插件对齐，不写死）。
dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
