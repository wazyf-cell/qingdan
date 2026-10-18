// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 界面偏好（M5 定案第 2、10 条）：默认打开哪个页签、要不要显示角标数字。
///
/// 存 SharedPreferences，**不进库、不参与同步**：手机想开课表、桌面想开清单，
/// 是这台设备自己的习惯，同步过去只会互相覆盖。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/shell/shell_tab.dart';

class SettingsModel extends ChangeNotifier {
  SettingsModel({SharedPreferences? prefs}) : _prefs = prefs;

  static const String kDefaultTabKey = 'ui.defaultTab';
  static const String kShowBadgesKey = 'ui.showBadges';

  /// 「设置」不当选项：它是从别处点进去的去处，不是开屏要看的东西。
  static const List<ShellTab> kDefaultTabChoices = <ShellTab>[
    ShellTab.tasks,
    ShellTab.chaoxing,
    ShellTab.course,
  ];

  final SharedPreferences? _prefs;

  ShellTab defaultTab = ShellTab.tasks;
  bool showBadges = true;

  Future<void> load() async {
    final SharedPreferences p = await _instance();
    final String? raw = p.getString(kDefaultTabKey);
    defaultTab = kDefaultTabChoices.firstWhere(
        (ShellTab t) => t.name == raw,
        orElse: () => ShellTab.tasks);
    showBadges = p.getBool(kShowBadgesKey) ?? true;
    notifyListeners();
  }

  Future<void> setDefaultTab(ShellTab tab) async {
    if (defaultTab == tab) return;
    defaultTab = tab;
    notifyListeners();
    await (await _instance()).setString(kDefaultTabKey, tab.name);
  }

  Future<void> setShowBadges(bool value) async {
    if (showBadges == value) return;
    showBadges = value;
    notifyListeners();
    await (await _instance()).setBool(kShowBadgesKey, value);
  }

  Future<SharedPreferences> _instance() async =>
      _prefs ?? await SharedPreferences.getInstance();
}
