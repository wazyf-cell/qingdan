import 'package:qingdan/domain/task.dart';

import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';

import 'task_pane_model.dart';

/// 视图过滤 + 排序（从 TaskPaneModel 抽出，纯逻辑便于复用）。

/// 把全量任务按视图 id 过滤（今天 / 最近 7 天 / 所有 / 已完成 / 用户清单）。
List<Task> filterForView(String viewId, List<Task> all) {
  final DateTime now = DateTime.now();
  final DateTime todayEnd =
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  switch (viewId) {
    case kSmartToday:
      return all
          .where((Task t) =>
              !t.completed &&
              t.dueDate != null &&
              t.dueDate!.toLocal().isBefore(todayEnd))
          .toList();
    case kSmartNext7:
      final DateTime end = todayEnd.add(const Duration(days: 6));
      return all
          .where((Task t) =>
              !t.completed &&
              t.dueDate != null &&
              t.dueDate!.toLocal().isBefore(end))
          .toList();
    case kSmartAll:
      return all.where((Task t) => !t.completed).toList();
    case kSmartCompleted:
      return all;
    default:
      if (viewId == kTrash) return const <Task>[];
      return all.where((Task t) => t.listId == viewId).toList();
  }
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
