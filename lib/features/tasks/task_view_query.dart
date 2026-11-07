import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_schedule.dart';

import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';

import 'task_pane_queries.dart';

/// 视图过滤 + 排序（从 TaskPaneModel 抽出，纯逻辑便于复用）。

/// 把全量任务按视图 id 过滤（今天 / 最近 7 天 / 所有 / 已完成 / 用户清单）。
/// [now] 只给测试注入固定时钟；生产用本机当前时间。
List<Task> filterForView(String viewId, List<Task> all, {DateTime? now}) {
  final DateTime at = now ?? DateTime.now();
  switch (viewId) {
    case kSmartToday:
      return all.where((Task t) => inToday(t, at)).toList();
    case kSmartNext7:
      return all.where((Task t) => inNext7(t, at)).toList();
    case kSmartAll:
      return all.where((Task t) => !t.completed).toList();
    case kSmartCompleted:
      return all;
    default:
      if (viewId == kTrash) return const <Task>[];
      return all.where((Task t) => t.listId == viewId).toList();
  }
}

/// 智能清单（今天/最近 7 天/所有）的排序：关注时间升序，同时间按标题。
/// [grouped] 为 true 时先按分组优先级（已过期→已开始→今天→明天→以后），
/// 保证组标题连续（今天/最近 7 天）；所有视图不分组，只按关注时间。
List<Task> sortSmartTasks(List<Task> list,
    {required bool grouped, required DateTime now}) {
  final List<Task> out = List<Task>.of(list);
  out.sort((Task a, Task b) {
    if (grouped) {
      final int g = groupRank(groupOf(a, now))
          .compareTo(groupRank(groupOf(b, now)));
      if (g != 0) return g;
    }
    final DateTime? af = focusOf(a);
    final DateTime? bf = focusOf(b);
    if (af == null && bf == null) return a.title.compareTo(b.title);
    if (af == null) return 1;
    if (bf == null) return -1;
    final int c = af.compareTo(bf);
    return c != 0 ? c : a.title.compareTo(b.title);
  });
  return out;
}

/// 已完成：完成时间倒序；缺失完成时间的旧数据回退到修改时间。
List<Task> sortCompletedTasks(List<Task> list) {
  final List<Task> out = List<Task>.of(list);
  out.sort((Task a, Task b) {
    final DateTime? at = a.completedTime?.toLocal();
    final DateTime? bt = b.completedTime?.toLocal();
    final DateTime? am = a.modifiedTime?.toLocal();
    final DateTime? bm = b.modifiedTime?.toLocal();
    final DateTime? ax = at ?? am;
    final DateTime? bx = bt ?? bm;
    if (ax == null && bx == null) return a.title.compareTo(b.title);
    if (ax == null) return 1;
    if (bx == null) return -1;
    final int c = bx.compareTo(ax);
    return c != 0 ? c : a.title.compareTo(b.title);
  });
  return out;
}

/// 排序：智能清单（今天/最近7天/所有）强制按到期时间（§4 决策），
/// 用户清单按 [mode]。不修改入参（入参可能是 const/unmodifiable 列表），
/// 返回排序后的新列表。
List<Task> sortTasks(List<Task> list, TaskSortMode mode, {required bool smart}) {
  final List<Task> out = List<Task>.of(list);
  final TaskSortMode effective = smart ? TaskSortMode.due : mode;
  switch (effective) {
    case TaskSortMode.manual:
      out.sort((Task a, Task b) => a.sortOrder.compareTo(b.sortOrder));
    case TaskSortMode.due:
      out.sort((Task a, Task b) {
        final DateTime? ad = a.dueDate;
        final DateTime? bd = b.dueDate;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    case TaskSortMode.priority:
      out.sort(
          (Task a, Task b) => b.priority.value.compareTo(a.priority.value));
    case TaskSortMode.title:
      out.sort((Task a, Task b) => a.title.compareTo(b.title));
  }
  return out;
}
