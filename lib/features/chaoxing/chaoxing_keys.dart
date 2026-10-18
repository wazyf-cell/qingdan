/// 学习通面板全部 ValueKey 的集中定义（M6B §B0）。
///
/// 之前 `lib/features/chaoxing/` 与 `lib/import/chaoxing/` 里一个 key 都没有，
/// 测试只能靠 `find.text` 猜，而文案一改测试就假绿。B1–B8 每条测试都要定位，
/// 所以先补这一份表；UI 里禁止再手写 key 字符串字面量。
library;

import 'package:flutter/widgets.dart';

abstract final class ChaoxingKeys {
  // ---- 头部一行 ----
  static const String tabHomework = 'cx-tab-homework';
  static const String tabActivity = 'cx-tab-activity';
  static const String stale = 'cx-stale';
  static const String refresh = 'cx-refresh';
  static const String filter = 'cx-filter';
  static const String account = 'cx-account';

  // ---- ⋮ 菜单三项（顺序：重新登录 / 隐藏列表 / 退出登录，破坏性放最后）----
  static const String menuRelogin = 'cx-menu-relogin';
  static const String menuHidden = 'cx-menu-hidden';
  static const String menuLogout = 'cx-menu-logout';

  // ---- 筛选弹层 ----
  static const String filterSearch = 'cx-filter-search';
  static const String filterCourse = 'cx-filter-course';
  static const String filterUnfinished = 'cx-filter-unfinished';
  static const String filterSubmittable = 'cx-filter-submittable';
  static const String filterSort = 'cx-filter-sort';
  static const String filterCount = 'cx-filter-count';
  static const String filterReset = 'cx-filter-reset';
  static const String filterApply = 'cx-filter-apply';

  // ---- 隐藏列表页 ----
  static const String hiddenRestoreAll = 'cx-hidden-restore-all';
  static const String hiddenPurgeDead = 'cx-hidden-purge-dead';

  // ---- 三种占位态 ----
  static const String login = 'cx-login';
  static const String empty = 'cx-empty';
  static const String banner = 'cx-banner';

  // ---- 逐条目的 key（task.key 里带 `|`，测试用拼接即可）----
  static String card(String taskKey) => 'cx-card-$taskKey';
  static String actDetail(String taskKey) => 'cx-act-detail-$taskKey';
  static String actHide(String taskKey) => 'cx-act-hide-$taskKey';
  static String hiddenRow(String taskKey) => 'cx-hidden-row-$taskKey';
  static String hiddenRestore(String taskKey) => 'cx-hidden-restore-$taskKey';
  static String sortOption(String name) => 'cx-filter-sort-$name';

  /// UI 与测试共用的 key 构造器（`Finder` 属于 flutter_test，lib 里不能引，
  /// 所以这里只出 [ValueKey]，测试写 `find.byKey(ChaoxingKeys.vkey(...))`）。
  static ValueKey<String> vkey(String id) => ValueKey<String>(id);
}
