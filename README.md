# ControlHub App

ControlHub 面板的 Android 客户端。Flutter 实现，支持白标：改配置文件和图标就能换成自己的品牌与服务器，不必动业务代码。

## 功能

- 邮箱密码登录，也支持用订阅链接直接登录
- 节点列表与测速（TCP 握手测物理延迟，UDP 传输走内核测速兜底）
- 一键连接（VLESS，含 Reality / XHTTP），可开启国内直连分流
- 套餐购买、优惠券、在线支付（内嵌网页支付，支持轮询到账）
- 流量统计：已用 / 剩余 / 到期时间
- 公告、使用教程、问题反馈、版本更新提示

## 环境要求

| 项目 | 版本 |
|---|---|
| Flutter | 3.47.8（Dart 3.13.7） |
| Android SDK | compileSdk / targetSdk 36，minSdk 24（Android 7.0 起） |
| JDK | 17 |

## 快速开始

```bash
flutter pub get
flutter run
```

## 指向自己的服务器

编辑 `assets/config/api_base.txt`（就一行地址）：

```
https://example.com
```

地址读取优先级：隐藏入口手动覆盖（调试用） > `api_base.txt` > 编译常量 `API_BASE`（`--dart-define`）。普通用户改这一个文件换服务器就够了。

## 改品牌

| 改什么 | 改哪里 |
|---|---|
| App 内显示的站点名 | `assets/config/app_name.txt`（留空则跟随服务端的 `site_title`） |
| 图标 | 替换 `assets/config/icon.png`，再跑 `dart run flutter_launcher_icons` |
| 桌面图标下的名字 | `android/app/src/main/AndroidManifest.xml` 的 `android:label` |
| 包名 | `android/app/build.gradle.kts` 里的 `val appId`（`namespace` 与 `applicationId` 共用这一处） |

App 内标题、多任务卡片、桌面图标名是三条独立来源，别只改一处就以为全改了。

## 构建

```bash
flutter build apk --release
```

- release 只打 `arm64-v8a`，产物约 32MB；debug 保留全架构给模拟器用。需要兼容 32 位老手机时，删掉 `android/app/build.gradle.kts` 里 `packaging.jniLibs.excludes` 那一段。
- 签名读 `android/app/key.properties`（`storeFile` / `storePassword` / `keyAlias` / `keyPassword`）。该文件缺失时会回退 debug 签名，只能用于本地调试，不能对外发布。

## 发布

打 tag 触发 GitHub Actions 编译并发布 Release：

```bash
git tag v1.0.3
git push origin v1.0.3
```

CI 用仓库 Secrets 里的 keystore（`KEYSTORE_BASE64` / `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD`）解码后签名，产物发布为 `app-release.apk`。首次冷缓存约 8-9 分钟，之后命中缓存一般 3-5 分钟。

维护时注意两件事，都踩过：

- 不要在 `android/gradle.properties` 里写本机代理。这是入库文件，CI 机器上没有那个代理，Gradle 下载依赖会全部失败。
- 签名不要用环境变量传 `android/app/x.jks` 这类相对路径：Gradle 按 app 模块解析，会变成 `android/app/android/app/x.jks`。统一走 `key.properties`。

## 目录结构

```
lib/core      配置（服务器地址/品牌名）、网络层、路由、主题、存储
lib/data      数据模型与仓库（登录、套餐、支付、订阅、公告等接口）
lib/features  页面：首页、节点、套餐、支付、公告、教程、反馈、设置、更新
lib/vpn       VPN 引擎封装、订阅解析、测速、分流
lib/widgets   公共组件
```

## 与服务端的关系

App 只是客户端，需要配套的 ControlHub 服务端提供接口：登录与站点配置、套餐与优惠券、支付下单与回调查询、订阅输出、公告教程、版本检查。服务端没有就绪时，App 能启动但任何数据都拉不到。
