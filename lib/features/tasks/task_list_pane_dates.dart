// 列表行菜单「编辑日期」的日期 + 可选时刻入口（M6-A §A3）。
//
// 从 task_list_pane.dart 拆出来有两个原因：那个文件已经 298 行触顶（300 上限），
// 而这条交互本身是独立的一段（选日子 → 问要不要给时刻 → 写 dueDate）。
// 行菜单在 task_row_menu.dart（不在本批改围），所以「设置时刻」做成日期选完后的
// 二级确认框，而不是菜单里再加一项 —— §A3 给的两种形状里取了这一种。

import 'package:flutter/material.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/tasks/date_time_pick.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';

/// 行菜单「编辑日期」：日历 → 二级确认是否补时刻 → 写 `dueDate`（走既有用例路径）。
Future<void> pickDueDateFromRowMenu(
    BuildContext context, TaskPaneModel model, Task task) async {
  final DateTime initial = task.dueDate?.toLocal() ?? DateTime.now();
  final DateTime? picked = await pickDateWithOptionalTime(
    context,
    initial: initial,
    helpText: '到期日期',
  );
  if (picked == null) return; // 取消日历 = 什么都不改
  if (!context.mounted) return;
  DateTime value = picked;
  final bool wantTime = await _askSetTime(context, picked);
  if (!context.mounted) return;
  if (wantTime) {
    final DateTime? withTime = await pickTimeFor(context, picked);
    // 日历已经选了日子，时刻那一步取消就按「没填时间」保存，不回滚日期。
    if (withTime != null) value = withTime;
  }
  await model.setDueDate(task, value);
}

/// 二级入口：问「要不要顺便给个具体时刻」。返回 false = 只记日期。
///
/// 刻意做成纯文案确认框、不放输入框：S5-f 那次真机红屏（`_dependents.isEmpty`）是
/// `TextEditingController` 在 `await showDialog` 之后才 dispose 造成的，这里不引入它。
Future<bool> _askSetTime(BuildContext context, DateTime date) async {
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      key: const ValueKey<String>('pick-due-time-ask'),
      content: Text('${date.month}/${date.day} 要同时指定几点几分吗？'
          '（不填就只记日期）'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('只记日期'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('设置时刻'),
        ),
      ],
    ),
  );
  return answer ?? false;
}
