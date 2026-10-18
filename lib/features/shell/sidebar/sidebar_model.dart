// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
import 'package:flutter/foundation.dart';

import 'package:qingdan/application/task_list_use_case.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/features/shell/shell_tab.dart';

/// 侧栏数据模型（已上移：UI 层不接触 DAO，读操作走 [TaskListUseCase]，
/// 原「M1 临时直读 DAO」手段随用例层就位移除）。
///
/// 另承载「当前选中项」状态：任务列表与侧栏共用（点击清单切列表）。
class SidebarModel extends ChangeNotifier {
  SidebarModel({required TaskListUseCase listUseCase})
      : _listUseCase = listUseCase;

  final TaskListUseCase _listUseCase;

  bool loaded = false;
  String? error;

  /// 用户清单（F6），按 sort_order 升序（含内置「收集箱」seed 行）。
  List<TaskList> lists = const <TaskList>[];

  /// 智能清单计数（§2.1：未完成数；「已完成」为累计完成数）。
  int todayCount = 0;
  int next7Count = 0;
  int allCount = 0;
  int completedCount = 0;

  final Map<String, int> _listCounts = <String, int>{};

  /// 当前选中项（智能清单 id 或用户清单 id 或 trash），默认「今天」。
  String selectedId = 'today';

  /// 窄屏底部页签（M5 定案第 1 条）。**不另立真相**：[selectedId] 仍是
  /// 「当前面板」的唯一权威，[tab] 只是它在窄屏上的投影——切页签写 selectedId，
  /// 改 selectedId 也会同步 tab，两边不会各说各话。
  ShellTab tab = ShellTab.tasks;

  /// 切去课表/学习通前记下的清单视图，切回「清单」页签时恢复。
  String _lastTaskView = kSmartToday;

  /// 指定清单的未完成数。
  int countFor(String listId) => _listCounts[listId] ?? 0;

  /// 选中项变化（侧栏点击 / 快捷键 Ctrl+1..4 / 回收站入口 / 清单半屏面板）。
  void select(String id) {
    if (selectedId == id) return;
    selectedId = id;
    tab = switch (id) {
      kChaoxing => ShellTab.chaoxing,
      kCourseWeek => ShellTab.course,
      _ => ShellTab.tasks,
    };
    if (tab == ShellTab.tasks) _lastTaskView = id;
    notifyListeners();
  }

  /// 窄屏底部页签切换。「设置」不是任务视图，所以它不动 [selectedId]——
  /// 从设置切回清单时，看到的还是离开时那个视图。
  void selectTab(ShellTab next) {
    if (next == tab) return;
    switch (next) {
      case ShellTab.tasks:
        selectedId = _lastTaskView;
      case ShellTab.chaoxing:
        _rememberTaskView();
        selectedId = kChaoxing;
      case ShellTab.course:
        _rememberTaskView();
        selectedId = kCourseWeek;
      case ShellTab.settings:
        break;
    }
    tab = next;
    notifyListeners();
  }

  void _rememberTaskView() {
    if (selectedId != kChaoxing && selectedId != kCourseWeek) {
      _lastTaskView = selectedId;
    }
  }

  /// 应用「默认打开的页面」（M5 定案第 2 条，启动时调一次）。
  ///
  /// 「清单」就是初始形态，直接返回：`selectTab` 对同值早退，但这里连早退都不必走。
  void applyDefaultTab(ShellTab next) {
    if (next == ShellTab.tasks) return;
    selectTab(next);
  }

  /// 加载清单与计数。失败时记录 [error] 并原样抛出，由入口呈现，不静默吞掉。
  Future<void> load() async {
    try {
      final SidebarSnapshot snap = await _listUseCase.loadSidebar();
      lists = snap.lists;
      todayCount = snap.todayCount;
      next7Count = snap.next7Count;
      allCount = snap.allCount;
      completedCount = snap.completedCount;
      _listCounts
        ..clear()
        ..addAll(snap.listCounts);
      loaded = true;
      error = null;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }
}

/// 智能清单固定 id（§3.4 Ctrl+1..4 与侧栏/列表共用）。
const String kSmartToday = 'today';
const String kSmartNext7 = 'next7';
const String kSmartAll = 'all';
const String kSmartCompleted = 'completed';
const String kTrash = 'trash';

/// 课表周视图（M4a）。与任务视图并列，走同一套侧栏/图标栏/抽屉导航。
const String kCourseWeek = 'course';

/// 学习通待办（手机版优先的新数据域）。同样是「一个 selectedId 一个面板」，
/// 但它不落库、不同步——数据每次现拉，见 chaoxing_model.dart 的定案注释。
const String kChaoxing = 'chaoxing';
