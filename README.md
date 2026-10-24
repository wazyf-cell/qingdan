# qingdan（自用任务清单）

给**一个人、多台设备**用的任务清单 App：数据完全归自己、可离线、能把课表与日历合并进来。
当前这一支**只发布 Android 端**（`android/`），桌面端目录不随仓库发布。

许可证：**GNU AGPL-3.0-or-later**（见 `LICENSE`）；移植来源与第三方依赖清单见 `NOTICE`。

---

## 这是什么

- **清单/任务**：清单、任务、子任务、标签、优先级、开始/到期日期、回收站；顶部一行文本
  快速创建（含自然语言日期）+ 右下角「＋」快捷添加抽屉。
- **课表**：周视图网格、学期与作息（可从模板快速生成 12 节课的作息）、手工加课、
  课程颜色、同槽多门课在一格里以 `⇄` 角标循环切换。
- **课表导入**：CSV / xlsx / `.wakeup_schedule` 文件，或从教务系统（强智）页面抓取，
  五步向导 + 人工校正 + 三模式（新增/更新/覆盖）+ 导入历史 + 批量修正；可导出 `.ics` / `.csv`。
- **学习通待办**：App 内 WebView 登录超星 → 直连它的 JSON/HTML 接口 → 列出还没交的作业、
  考试与课堂活动，含截止倒计时与提醒。**这是外部只读快照：刻意不落本地库、不参与同步。**
- **同步**：op-log + 字段级 LWW + 三路合并，后端可选**本地文件夹**或 **WebDAV**（如坚果云）。
- **通知**：到期/紧急提醒的本地排程通知（非精确闹钟 + 变更后防抖重排）。
- 窄屏（<720dp）为底部 4 页签：清单 / 学习通 / 课表 / 设置；宽屏为两栏布局。

## 不做什么（需求定死，不是实现细节）

- **没有自建服务端**，也没有任何后端账号体系。数据只在你自己的设备与你自己选的 WebDAV 里。
- **界面只有简体中文**，没有做 i18n，也没有排期。
- **没有全局搜索**（只有清单页/学习通面板内的标题过滤）。
- 学习通数据不落库、不同步、不写回（不会把「已完成」同步到没登录超星的那台设备）。
- 没有 iOS 端；Windows 端在本分支视为不存在。

## 环境要求

实测通过的组合（换版本请自行验证，见下方警告）：

| 项 | 版本 | 说明 |
| --- | --- | --- |
| Flutter | **3.47.5** stable | CI 也钉这个值（`.github/workflows/android-release.yml`） |
| Dart | 3.13.4 | 随 Flutter 3.47.5 |
| JDK | **17** | `android/app/build.gradle.kts` 里 `compileOptions` 与 Kotlin `jvmTarget` 都钉 17 |
| Gradle | 9.3.1 | wrapper 声明的发行版（`android/gradle/wrapper/gradle-wrapper.properties`） |
| Android Gradle Plugin | 9.1.0 | `android/settings.gradle.kts` |
| Kotlin | 2.4.0 | `android/settings.gradle.kts` |
| compileSdk / targetSdk / minSdk | 36 / 36 / 24 | 由 `flutter.compileSdkVersion` 等**随 Flutter 版本解析** |
| NDK | 28.2.13676358 | 同上，随 Flutter 版本 |
| Android SDK | Platform 36 + Build-Tools | 经 `sdkmanager` 或 Android Studio 安装 |
| 磁盘/内存 | 构建期 Gradle 堆为 `-Xmx8G` | 见 `android/gradle.properties`，机器不够可自行调低 |

> ⚠ **别顺手升 Flutter**。`compileSdk` / `minSdk` / `targetSdk` / `NDK` 全部取自 Flutter
> 工具链的默认值，升一个 Flutter 小版本会同时改动这四项，并可能连带要求升 AGP；
> 依赖里还有 `flutter_inappwebview ^6.2.0-beta.3`（用 beta 是因为稳定版自带的 Android 子包
> 使用了被 AGP 拒绝的 `proguard-android.txt`，理由写在 `pubspec.yaml` 注释里）。

## 三步出包

```bash
# 1) 装依赖（首次或换机器后）
flutter pub get

# 2) 连上一台 Android 设备/模拟器，直接跑起来看效果
flutter devices
flutter run -d <device-id>

# 3) 出正式 APK（按 ABI 分包，可直接安装）
flutter build apk --release --split-per-abi
```

产物在 `build/app/outputs/flutter-apk/`：

- `app-arm64-v8a-release.apk` —— 现在大多数手机
- `app-armeabi-v7a-release.apk` —— 老 32 位设备
- `app-x86_64-release.apk` —— 模拟器

**关于 Gradle wrapper**：`android/gradle/wrapper/gradle-wrapper.jar`、`gradlew`、`gradlew.bat`
被 `android/.gitignore` 排除，**仓库里没有它们**。`flutter build` / `flutter run` 不受影响
（Flutter 在构建前会自动注入 wrapper）。但**干净 clone 上直接 `cd android && ./gradlew assembleRelease`
会失败** —— 这不是仓库坏了；真要用裸 Gradle，先在有 Gradle 的机器上 `gradle wrapper` 生成一次。

## 签名与升级注意（装真机前必读）

- 正式签名走 `android/key.properties`（**不入库**）。仓库只发布模板
  `android/key.properties.example`，复制成 `key.properties` 再填自己的值，生成钥匙的命令
  与注意事项都写在那份模板里。
- 没有 `key.properties` 时 release 构建会**退回 debug 签名**，并在配置期打印一条
  WARNING。这种包只能自测，不能对外发。
- **同一把签名的版本可以覆盖安装，数据不丢；别的签名的旧包（自己编译的 debug 版、
  共存版）必须先卸载一次，卸载会清空 `files/qingdan.db`** —— 任务、清单、学期、作息、
  课表全在里面。卸载前先确认同步已完成或已导出。
- 应用内的「检测更新 → 下载并安装」（1.0.4）会在下载后**先比对签名**：不一致就不进
  系统安装器，直接说明需要卸载；一致则调起系统安装器（用户仍要点一次「安装」，
  普通应用无权跳过）。

## 版本号规则

- **唯一真相是 `pubspec.yaml` 的 `version:`**（形如 `1.0.1+2`：`+` 前是 versionName，
  后面是 versionCode）。
- 发布目前是**本机出包、手工上传**：`flutter build apk --release --split-per-abi`，把产物与
  `sha256sums.txt` 挂到 Release 页面。正式签名钥匙不离开本机，GitHub 上也没有它的副本。
- CI 工作流的 **tag 触发已暂停**（仓库没配 `KEYSTORE_BASE64` / `KEYSTORE_PASSWORD` 两个 Secret，
  加了 tag 触发也会在还原密钥那一步失败）：现在打 tag 不会触发构建。
- 手动 Run workflow 是「彩排」：跑完 analyze、测试、构建与签名核对（硬比对证书指纹），
  但**不创建 Release、也不上传任何产物**（公开仓库的 Actions 产物不登录就能下载，
  没经你过目的包不该挂上去）。

## 怎么跑测试

```bash
flutter analyze
flutter test --concurrency=1
```

> **`--concurrency=1` 不是可选的**：Windows 上多个测试文件并发会争抢 sqflite 而卡死。
> CI 用的也是这条命令。当前基线：`flutter analyze` 0 告警、全量测试全绿。

## 首次运行要自备什么

- **学习通账号**：在 App 内 WebView 自己登录；导出的 cookie 只进**系统凭据库**
  （Android Keystore / Windows 凭据管理器），不写进数据库、不进日志。
- **教务系统账号与网络**：「从教务系统抓取」要求你能访问本校教务站点——**多数教务只在校内网
  可达**，校外网络与模拟器上都打不通，这不是 App 的 bug。
- **WebDAV（可选）**：地址 + 账号 + 口令（口令同样只进系统凭据库）。用坚果云时需要
  「应用密码」，并且同步目录由 App 自己 `MKCOL` 创建。
- **通知权限**：Android 13+ 要手动授予，否则提醒静默失效。
- **明文 HTTP**：`AndroidManifest.xml` 里开了 `usesCleartextTraffic="true"`，因为教务站点
  多为 http（Android 默认禁明文）。代价与说明写在清单的注释里；不接受的话，自己关掉即可，
  只影响教务抓取。
- 学号、姓名、课程名之类**不会**被写进仓库；示例一律用「课程甲」「第一次作业」。

## 目录结构

```text
lib/
  domain/        纯数据与规则，无 IO
  application/   用例层 —— 所有写操作的唯一入口
  data/          SQLite DAO、迁移、凭据库
  sync/          同步引擎、意图推导、三路合并、后端实现、协调器
  import/        课表与学习通导入管道（course/ jiaowu/ chaoxing/）
  notify/        通知排程（纯函数）+ 闹钟接线
  features/      界面：shell / tasks / detail / calendar / course / settings / trash
test/            单元与 widget 测试
android/         Android 工程
.github/         CI（手动触发：analyze / 测试 / 构建 / 签名核对；发布走本机出包）
```

分层约定：UI 层不得直接访问 DAO，只调用 `lib/application/`；写库与记录待同步意图必须在
同一事务内；单一源码文件不超过 300 行。

## 第三方与许可证

- 本仓库整体以 **AGPL-3.0-or-later** 发布（`LICENSE`）。改代码后再分发（包括把它做成
  网络服务给别人用）需要同等地延续 AGPL 并公开对应源码。
- 采用 AGPL 而非 MIT 的直接原因：`lib/import/chaoxing/*.dart` 的接口契约移植自
  AGPL-3.0-or-later 的油猴脚本（上游 `Cooanyh/chaoxing-list`），派生作品必须延续同种
  copyleft。
- 逆向参考项目（WakeUp 课程表、TickTick 的同步合并算法）只借算法与数据结构、未拷贝实现
  或二进制；**每个移植文件的头部都写明了原路径、原类名与参考行号**，汇总见 `NOTICE`。
- 依赖清单与用途见 `NOTICE` 第三节。要精确的上游许可证全文：pub.dev 每个包的页面都有
  LICENSE 标签；本机已解析的包目录里也带着 `LICENSE` 文件，位置用
  `dart pub cache list` 或 `dart pub deps` 查（形如
  `<PUB_CACHE>/hosted/pub.dev/<包名>-<版本>/LICENSE`）。

## 隐私

仓库是公开的，所以这里的规矩是：**不放**真实课表、真实作业标题、教师名、学号、账号、
未打码的截图原图与任何凭据；文档与测试里的示例一律写「课程甲」「第一次作业」。
数据库文件（`qingdan.db`）、签名钥匙与 `key.properties` 都在 `.gitignore` 里明确排除，
不要绕过。本地保留的过程文档（需求、素材、变更日志）含真实信息，因此**不随本仓库发布**。
