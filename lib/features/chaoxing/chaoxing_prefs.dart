// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 学习通视图偏好的本地存取（SharedPreferences，键前缀 `chaoxing.view.`）。
///
/// 只存工具栏开关与隐藏标记；搜索词与课程筛选是会话态，不落盘。
/// **不进数据库、不参与同步**——偏好只对这台设备有意义。
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'chaoxing_grouping.dart';
import 'chaoxing_hidden_entry.dart';

class ChaoxingPrefs {
  ChaoxingPrefs({SharedPreferences? prefs}) : _prefs = prefs;

  static const String kHiddenKey = 'chaoxing.view.hidden';
  static const String kOnlyUnfinishedKey = 'chaoxing.view.onlyUnfinished';
  static const String kOnlySubmittableKey = 'chaoxing.view.onlySubmittable';
  static const String kSortByKey = 'chaoxing.view.sortBy';
  static const String kTabKey = 'chaoxing.view.tab';

  /// 隐藏项的展示元数据（M6B §B6 登记在总纲 §五；形状是 JSON 对象，默认 `{}`）。
  static const String kHiddenMetaKey = 'chaoxing.hidden.meta';

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

  /// 隐藏项元数据（损坏时 `ChaoxingHiddenEntry.decode` 已降级成空表，不抛）。
  Future<List<ChaoxingHiddenEntry>> loadHiddenMeta() async {
    final SharedPreferences p = await _prefsInstance();
    return ChaoxingHiddenEntry.decode(p.getString(kHiddenMetaKey));
  }

  Future<void> saveHiddenMeta(List<ChaoxingHiddenEntry> entries) async {
    final SharedPreferences p = await _prefsInstance();
    await p.setString(kHiddenMetaKey, ChaoxingHiddenEntry.encode(entries));
  }

  /// 「退出并清空隐藏列表」用：隐藏集与元数据必须一起删，
  /// 只删一个会留下渲染不出来的孤儿项。
  Future<void> clearHiddenList() async {
    final SharedPreferences p = await _prefsInstance();
    await p.remove(kHiddenKey);
    await p.remove(kHiddenMetaKey);
  }

  /// 存的是枚举名，读回来认不出就用默认值（旧版本留下的脏键不该让面板崩）。
  T _enumOf<T>(String? raw, List<T> values, T fallback) {
    for (final T v in values) {
      if ('$v'.split('.').last == raw) return v;
    }
    return fallback;
  }
}
