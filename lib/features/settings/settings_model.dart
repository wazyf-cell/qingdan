// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 界面偏好（M5 定案第 2、10 条 + M6-A4 回收站阈值）：默认打开哪个页签、
/// 要不要显示角标数字、回收站多少天后自动清空。
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

  /// 首启使用说明引导是否已看过（M6-C6，key 登记于总纲 §五）。
  /// 「以后再说」也置 true——用户裁决 Q26：只打扰一次。
  static const String kGuideSeenKey = 'ui.guideSeen';

  /// 回收站自动清空阈值（M6-A4，key 登记于总纲 §五）。`0` = 永不。
  /// 合法值固定四档，读回非法值（手改 prefs / 旧版本残留）一律回退 [kTrashPurgeDaysDefault]。
  static const String kTrashPurgeDaysKey = 'trash.purgeDays';
  static const int kTrashPurgeDaysDefault = 30;
  static const List<int> kTrashPurgeDaysChoices = <int>[0, 7, 30, 90];

  /// 「设置」不当选项：它是从别处点进去的去处，不是开屏要看的东西。
  static const List<ShellTab> kDefaultTabChoices = <ShellTab>[
    ShellTab.tasks,
    ShellTab.chaoxing,
    ShellTab.course,
  ];

  final SharedPreferences? _prefs;

  ShellTab defaultTab = ShellTab.tasks;
  bool showBadges = true;

  /// 首启引导只在没看过时弹一次（`false` = 新装或清了应用数据）。
  bool guideSeen = false;

  /// 回收站在「应用打开时检查」里超过该天数即物理清空（M6-A4）；0 = 永不。
  int trashPurgeDays = kTrashPurgeDaysDefault;

  Future<void> load() async {
    final SharedPreferences p = await _instance();
    final String? raw = p.getString(kDefaultTabKey);
    defaultTab = kDefaultTabChoices.firstWhere(
        (ShellTab t) => t.name == raw,
        orElse: () => ShellTab.tasks);
    showBadges = p.getBool(kShowBadgesKey) ?? true;
    guideSeen = p.getBool(kGuideSeenKey) ?? false;
    final int? days = p.getInt(kTrashPurgeDaysKey);
    trashPurgeDays =
        (days != null && kTrashPurgeDaysChoices.contains(days))
            ? days
            : kTrashPurgeDaysDefault;
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

  /// 记下「引导已经看过」。**只在真要消失它时调**（两个按钮都算看过）。
  Future<void> setGuideSeen(bool value) async {
    if (guideSeen == value) return;
    guideSeen = value;
    notifyListeners();
    await (await _instance()).setBool(kGuideSeenKey, value);
  }

  /// 设置回收站清空阈值；非法值（不在 [kTrashPurgeDaysChoices]）回退默认 30。
  Future<void> setTrashPurgeDays(int days) async {
    final int value = kTrashPurgeDaysChoices.contains(days)
        ? days
        : kTrashPurgeDaysDefault;
    if (trashPurgeDays == value) return;
    trashPurgeDays = value;
    notifyListeners();
    await (await _instance()).setInt(kTrashPurgeDaysKey, value);
  }

  Future<SharedPreferences> _instance() async =>
      _prefs ?? await SharedPreferences.getInstance();
}
