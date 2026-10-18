import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式状态（§1.2：浅 / 深 / 跟随系统三选项，切换即时生效）。
///
/// 切换即写入 `shared_preferences`（key = `theme.mode`），
/// [loadPersisted] 在 main 中于 runApp 前调用，重启恢复上次选择。
class ThemeModeModel extends ChangeNotifier {
  ThemeModeModel(this._mode);

  static const String _kPrefKey = 'theme.mode';

  ThemeMode _mode;

  ThemeMode get mode => _mode;

  /// 设置主题并持久化；持久化失败不影响内存态生效（下次启动回退旧值）。
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, mode.name);
  }

  /// 从持久化读取上次选择；无记录 / 值损坏时保持默认（跟随系统）。
  Future<void> loadPersisted() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_kPrefKey);
    if (raw == null) return;
    for (final ThemeMode m in ThemeMode.values) {
      if (m.name == raw) {
        _mode = m;
        return;
      }
    }
  }
}
