/// 系统凭据库接口（M3 §3.1：云盘密码只进系统凭据库的铁律在代码上的唯一出口）。
///
/// 抽成接口而不是直接依赖 [FlutterSecureStorage] 的原因（M3 任务书 S2 坑）：
/// flutter_secure_storage 在纯 Dart 单测里没有平台实现，直接调用会抛
/// MissingPluginException。SyncConfigStore 依赖本接口后，测试注入内存实现
/// 即可离线验证「密码走 secure storage 而非 prefs」，不必起平台通道。
///
/// [SecureStorageStore] 是唯一生产实现，内部仍用 flutter_secure_storage
/// （Windows → 凭据管理器，Android → Keystore），未换任何存储介质。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 系统凭据库的键值存取（字符串）。
abstract class SecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// 生产实现：flutter_secure_storage（双端系统凭据库）。
class SecureStorageStore implements SecureStore {
  SecureStorageStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 内存实现（仅测试用）。生产代码不得引用。
class InMemorySecureStore implements SecureStore {
  InMemorySecureStore([Map<String, String>? seed])
      : _data = <String, String>{...?seed};

  final Map<String, String> _data;

  /// 供测试断言「密码确实落在这里而非 prefs」。
  Map<String, String> get entries => Map<String, String>.unmodifiable(_data);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}
