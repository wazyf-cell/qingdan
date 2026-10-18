// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 同步配置的读写（M3 §3.2）。
///
/// 存储分工是安全铁律的体现：非敏感项（开关 / 后端类型 / 地址 / 账号）进
/// shared_preferences；**应用密码进系统凭据库**（[SecureStore]），两者物理
/// 分离，杜绝「配置文件里带密码」。
///
/// 刻意不引入 JSON 配置文件：SharedPreferences 已是项目既有先例
/// （theme_mode_model.dart），再开一套文件格式只增维护面。
///
/// 密码例外：Windows 凭据管理器不支持空值，因此「密码为空」在凭据库里
/// 表示为「条目不存在」——读回空串、保存空串则删除条目。读取其余四项失败
/// 时回退默认值（如 prefs 尚未就绪），但**密码区失败不吞**：静默把密码
/// 读成空会让用户以为「只是没同步」，实际是配置丢失，必须冒泡。
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'secure_store.dart';

/// 同步配置快照。字段全部非空字符串（空串 = 未设置）。
class SyncConfig {
  const SyncConfig({
    this.enabled = false,
    this.backendType = kBackendWebDav,
    this.baseUrl = '',
    this.username = '',
    this.password = '',
    this.credentialMissing = false,
  });

  /// 同步开关；关 = 停掉全部自动触发（手动同步仍可用，§3.2）。
  final bool enabled;

  /// 后端类型；配置与 UI 目前只认 [kBackendWebDav] 这一个取值。
  ///
  /// 原括注「localFolder 未实现」已过期于 M2 收口：本地文件夹后端早就在
  /// `local_folder_backend.dart`（配套 `test/local_folder_backend_test.dart`），
  /// 缺的只是把它接进配置——它没有自己的常量、设置页也不露出，而 [isConfigured]
  /// 对 webdav 以外的一律判未配置（所以下面那行 `backendType == kBackendWebDav`
  /// 不是冗余）。
  final String backendType;

  /// 服务器地址（WebDAV 根，**必须带非空子路径**，见 §6.1）。
  final String baseUrl;

  /// 账号（坚果云邮箱/手机号，非敏感）。
  final String username;

  /// 应用密码（坚果云「安全选项 → 添加应用密码」生成）。
  final String password;

  /// 地址/账号都在、唯独密码从凭据库读不回来（2026-10-11 Android 真机实测：
  /// 模拟器 Keystore 在新进程里解不开自己写的条目，同文件的 prefs 却正常）。
  ///
  /// 必须与「从没配过」分开：两者在 [isConfigured] 上同为 false，但用户该做
  /// 的事完全不同——一个是去填表，一个是重输一次密码。混起来的话界面只会
  /// 说「同步未配置」，人就去翻配置页，看不出凭据库已经坏了。
  final bool credentialMissing;

  /// 是否已有足够配置可以尝试同步：开关开 + 三要素齐全。
  bool get isConfigured =>
      enabled &&
      backendType == kBackendWebDav &&
      baseUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  SyncConfig copyWith({
    bool? enabled,
    String? backendType,
    String? baseUrl,
    String? username,
    String? password,
    bool? credentialMissing,
  }) =>
      SyncConfig(
        enabled: enabled ?? this.enabled,
        backendType: backendType ?? this.backendType,
        baseUrl: baseUrl ?? this.baseUrl,
        username: username ?? this.username,
        password: password ?? this.password,
        credentialMissing: credentialMissing ?? this.credentialMissing,
      );
}

/// 目前仅支持 WebDAV；localFolder 后端（M2 已有实现）留给调试，UI 不露出。
const String kBackendWebDav = 'webdav';

/// 同步配置存取。存储键前缀 `sync.`（§3.2），密码键单列。
class SyncConfigStore {
  SyncConfigStore({SharedPreferences? prefs, SecureStore? secure})
      : _prefs = prefs,
        _secure = secure ?? SecureStorageStore();

  static const String kEnabledKey = 'sync.enabled';
  static const String kBackendTypeKey = 'sync.backendType';
  static const String kBaseUrlKey = 'sync.webdav.baseUrl';
  static const String kUsernameKey = 'sync.webdav.username';
  static const String kPasswordKey = 'sync.webdav.password';

  final SharedPreferences? _prefs;
  final SecureStore _secure;

  Future<SharedPreferences> _prefsInstance() async =>
      _prefs ?? await SharedPreferences.getInstance();

  /// 读取全部配置。prefs 区缺失回退默认；密码区失败冒泡（见文件头注释）。
  ///
  /// 「密码读回 null」不抛错也**不能当没配过**：插件在凭据库解不开时返回
  /// null 而非抛异常，所以这里用 [SyncConfig.credentialMissing] 把它显式带
  /// 出去，由协调器转成「需要重新配置」态。
  Future<SyncConfig> load() async {
    final SharedPreferences prefs = await _prefsInstance();
    final String? password = await _secure.read(kPasswordKey);
    final bool enabled = prefs.getBool(kEnabledKey) ?? false;
    final String backendType =
        prefs.getString(kBackendTypeKey) ?? kBackendWebDav;
    final String baseUrl = prefs.getString(kBaseUrlKey) ?? '';
    final String username = prefs.getString(kUsernameKey) ?? '';
    final bool readyExceptSecret = enabled &&
        backendType == kBackendWebDav &&
        baseUrl.trim().isNotEmpty &&
        username.trim().isNotEmpty;
    return SyncConfig(
      enabled: enabled,
      backendType: backendType,
      baseUrl: baseUrl,
      username: username,
      password: password ?? '',
      credentialMissing: readyExceptSecret && password == null,
    );
  }

  /// 保存配置。密码为空时删除凭据库条目（见文件头注释），不写入空值。
  Future<void> save(SyncConfig config) async {
    final SharedPreferences prefs = await _prefsInstance();
    await prefs.setBool(kEnabledKey, config.enabled);
    await prefs.setString(kBackendTypeKey, config.backendType);
    await prefs.setString(kBaseUrlKey, config.baseUrl);
    await prefs.setString(kUsernameKey, config.username);
    if (config.password.isEmpty) {
      await _secure.delete(kPasswordKey);
    } else {
      await _secure.write(kPasswordKey, config.password);
    }
  }

  /// 「解除配置」：清凭据库 + 停用同步 + 清空地址/账号（§3.3 按钮语义）。
  Future<void> clear() async {
    final SharedPreferences prefs = await _prefsInstance();
    await _secure.delete(kPasswordKey);
    await prefs.setBool(kEnabledKey, false);
    await prefs.setString(kBaseUrlKey, '');
    await prefs.setString(kUsernameKey, '');
  }
}
