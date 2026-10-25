# 贡献指南

这是一个以自用为主、公开发布的 Android Flutter 项目。提交 Issue 或 PR 前，请先读
README 的「使用说明」「免责声明与反馈」和本文件。

## 适用范围

- 只维护 Android 端；仓库不包含 Windows 桌面端，也没有自建服务端。
- 课表解析只按**南昌航空大学强智教务**的页面结构适配；其他学校/系统不属于本项目
  的适配范围，欢迎 fork 后自行修改。
- 不接受把项目改成需要自建服务器、账号体系或云端存储的 PR。

## 开发与验证

环境：Flutter `3.47.5`、Dart `3.13.4`、JDK 17（详见 README）。

```bash
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter build apk --debug
```

- `--concurrency=1` 是硬要求：多个测试文件并发会争抢 sqflite 而卡死。
- 单一源码文件不超过 300 行；新增行为要有测试。
- UI 改动请分别在手机宽度（411dp）与宽屏（1280dp）各验证一次；涉及可见反馈的改动
  最好附截图（截图必须遮掉真实任务、课程、账号信息）。

## PR 约定

- 一个 PR 只做一件事；说明「改了什么、怎么验证、有没有碰数据/同步/更新」。
- **不要**在 PR 里修改版本号、签名配置、`kRepoSlug` 更新地址或发布工作流；
  这些属于维护者的发布契约，需要单独讨论。
- 不要提交真实课表、作业标题、教师姓名、学号、账号、cookie、WebDAV 地址或截图原图。
- 不要用 `git add -f` 绕过 `.gitignore`，也不要把本地 `开发文档/`、`需求总结/`、
  `相关来源或素材/`、`扩展/` 或任何备份数据库带进仓库。
- 安全相关问题不要开公开 Issue，请按 `SECURITY.md` 私密报告。
- 提交即表示同意按仓库的 AGPL-3.0-or-later 许可分发你的贡献。

## 自己构建 / Fork

官方 APK 只由维护者用正式密钥签名。自己构建的包签名不同，**不能直接覆盖安装官方包**；
覆盖安装会失败，卸载又会清空本地数据库。请先导出课表并完成 WebDAV 同步。

如果要做一个可独立安装、可独立更新的 fork：

1. 改 `applicationId`（如 `com.example.qingdan`），避免与官方包冲突；
2. 生成自己的签名密钥，按 `android/key.properties.example` 配置；
3. 改 `lib/update/update_checker.dart` 的仓库地址与发布说明，别去查官方 Releases；
4. 自己负责版本号、Release 资产和用户数据迁移；不要复用官方签名或伪装成官方包。

## 发布

发布由维护者在本机完成：升 SemVer `versionName` 与 `versionCode`、本机签名、打
`vX.Y.Z` tag、上传 APK 与 sha256。历史上有过一次同版本 `v1.0.10-build12` 的例外；
新版本不要再发同版本 tag，否则应用内更新比较会认为「已是最新」。

## 许可证

AGPL-3.0-or-later。移植来源与第三方依赖的声明见 `NOTICE`；修改或分发时请保留
相应文件头与来源说明。
