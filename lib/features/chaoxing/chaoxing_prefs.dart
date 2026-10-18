// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 学习通视图偏好的本地存取（SharedPreferences，键前缀 `chaoxing.view.`）。
///
/// 只存工具栏开关与隐藏标记；搜索词与课程筛选是会话态，不落盘。
/// **不进数据库、不参与同步**——偏好只对这台设备有意义。
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'chaoxing_grouping.dart';

class ChaoxingPrefs {
  ChaoxingPrefs({SharedPreferences? prefs}) : _prefs = prefs;

  static const String kHiddenKey = 'chaoxing.view.hidden';
  static const String kOnlyUnfinishedKey = 'chaoxing.view.onlyUnfinished';
  static const String kOnlySubmittableKey = 'chaoxing.view.onlySubmittable';
  static const String kSortByKey = 'chaoxing.view.sortBy';
  static const String kTabKey = 'chaoxing.view.tab';

  final SharedPreferences? _prefs;

  Future<SharedPreferences> _prefsInstance() async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<ChaoxingViewSettings> load() async {
    final SharedPreferences p = await _prefsInstance();
    const ChaoxingViewSettings d = ChaoxingViewSettings();
    return ChaoxingViewSettings(
      hidden: (p.getStringList(kHiddenKey) ?? const <String>[]).toSet(),
      onlyUnfinished: p.getBool(kOnlyUnfinishedKey) ?? d.onlyUnfinished,
      onlySubmittable: p.getBool(kOnlySubmittableKey) ?? d.onlySubmittable,
      sortBy: _enumOf<ChaoxingSortBy>(
          p.getString(kSortByKey), ChaoxingSortBy.values, d.sortBy),
      tab: _enumOf<ChaoxingTab>(p.getString(kTabKey), ChaoxingTab.values, d.tab),
    );
  }

  Future<void> save(ChaoxingViewSettings s) async {
    final SharedPreferences p = await _prefsInstance();
    await p.setStringList(kHiddenKey, s.hidden.toList());
    await p.setBool(kOnlyUnfinishedKey, s.onlyUnfinished);
    await p.setBool(kOnlySubmittableKey, s.onlySubmittable);
    await p.setString(kSortByKey, s.sortBy.name);
    await p.setString(kTabKey, s.tab.name);
  }

  /// 存的是枚举名，读回来认不出就用默认值（旧版本留下的脏键不该让面板崩）。
  T _enumOf<T>(String? raw, List<T> values, T fallback) {
    for (final T v in values) {
      if ('$v'.split('.').last == raw) return v;
    }
    return fallback;
  }
}
