import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/features/tasks/compose_date_time_row.dart';
import 'package:qingdan/features/tasks/due_format.dart';
import 'package:qingdan/features/tasks/quick_compose_rows.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 详情面板属性行（§2.3）：清单 / 优先级 / 开始 / 结束 / **到期**，每行 36dp，
/// 标签 12sp 次要文字 + 值 14sp。移动形态下由 [DetailAttributes.build] 走 2 列。
///
/// 「到期」这一行是 M6-A §A3 补的：智能清单「今天 / 最近 7 天」和后续的通知**只认
/// `dueDate`**，而这里原先只有开始/结束——用户在手机上给「结束」填的时刻对通知无效。
class DetailAttributes extends StatelessWidget {
  const DetailAttributes({
    super.key,
    required this.task,
    required this.lists,
    required this.onPickList,
    required this.onPickPriority,
    required this.onPickStartDate,
    required this.onPickEndDate,
    this.onPickDueDate,
    this.pickDate,
    this.pickTime,
    this.twoColumns = false,
  });

  final Task task;
  final List<TaskList> lists;
  final ValueChanged<String?> onPickList;
  final ValueChanged<TaskPriority> onPickPriority;
  final ValueChanged<DateTime?> onPickStartDate;
  final ValueChanged<DateTime?> onPickEndDate;

  /// 「到期」写回调。可空：`detail_pane.dart` 不在本批改围内，缺席时走
  /// [_writeDue] 里的既有用例路径兜底。
  final ValueChanged<DateTime?>? onPickDueDate;

  /// 选择器接缝（默认真日历/真表盘），给 widget 测试用。
  final DateFieldPicker? pickDate;
  final DateFieldPicker? pickTime;
  final bool twoColumns;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pickRows = <Widget>[
      _listRow(context),
      _priorityRow(context),
    ];
    // 三行顺序固定：开始 / 结束 / 到期（§A3）。
    final List<Widget> dateRows = <Widget>[
      _dateRow(
        context,
        rowKey: 'detail-start',
        label: '开始',
        value: task.startDate?.toLocal(),
        onChanged: onPickStartDate,
      ),
      _dateRow(
        context,
        rowKey: 'detail-end',
        label: '结束',
        value: task.endDate?.toLocal(),
        onChanged: onPickEndDate,
      ),
      _dateRow(
        context,
        rowKey: 'detail-due',
        label: '到期',
        value: task.dueDate?.toLocal(),
        onChanged: (DateTime? v) => _writeDue(context, v),
      ),
    ];
    if (!twoColumns) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[...pickRows, ...dateRows],
      );
    }
    // 移动全屏详情：清单/优先级还能两列并排，日期行**必须整行**——半栏只有约
    // 190dp，值 + 行尾时刻钮放不下（S4b 那几处移动端溢出事故就是这个尺寸）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: pickRows[0]),
            Expanded(child: pickRows[1]),
          ],
        ),
        ...dateRows,
      ],
    );
  }

  /// 到期日期的写入：外部回调优先，缺席时用既有那条
  /// `TaskPaneModel.setDueDate` → `TaskUseCase.update`（一次写完整个字段，
  /// 不拆成多个 setter —— 总纲陷阱表第 8 条）。
  void _writeDue(BuildContext context, DateTime? value) {
    final ValueChanged<DateTime?>? external = onPickDueDate;
    if (external != null) {
      external(value);
      return;
    }
    // 清空需要一个能写 null 的用例入口（`Task.copyWith` 做不到），本批没做，
    // 所以这一行也不渲染 ✕（见 ComposeDateTimeRow.clearable）。
    if (value == null) return;
    // 这个回调是在选择器 await 之后才被调起来的，页面可能已经关掉 → 先确认还挂着。
    if (!context.mounted) return;
    context.read<TaskPaneModel?>()?.setDueDate(task, value);
  }

  Widget _listRow(BuildContext context) {
    String name = '收集箱';
    for (final TaskList list in lists) {
      if (list.id == task.listId) name = list.name;
    }
    return ComposeRow(
      height: 36,
      label: '清单',
      child: _AttrPopup<String>(
        value: task.listId,
        items: <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
              value: '', child: Text('收集箱', style: TextStyle(fontSize: 14))),
          for (final TaskList list in lists)
            PopupMenuItem<String>(
                value: list.id,
                child: Text(list.name, style: const TextStyle(fontSize: 14))),
        ],
        onSelected: (String? v) => onPickList(v!.isEmpty ? null : v),
        child: Text(name, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget _priorityRow(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color? color = priorityColor(task.priority, colors);
    return ComposeRow(
      height: 36,
      label: '优先级',
      child: _AttrPopup<TaskPriority>(
        value: task.priority,
        items: <PopupMenuEntry<TaskPriority>>[
          for (final TaskPriority p in TaskPriority.values)
            PopupMenuItem<TaskPriority>(
              value: p,
              child: Row(children: <Widget>[
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: priorityColor(p, colors) ??
                        colors.textFaint.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: AppDimens.s8),
                Text(priorityLabel(p), style: const TextStyle(fontSize: 14)),
              ]),
            ),
        ],
        onSelected: (TaskPriority? p) {
          if (p != null) onPickPriority(p);
        },
        child: Row(children: <Widget>[
          if (color != null)
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          if (color != null) const SizedBox(width: AppDimens.s8),
          Text(priorityLabel(task.priority),
              style: const TextStyle(fontSize: 14)),
        ]),
      ),
    );
  }

  /// 日期行：与快捷抽屉同一个组件（`§A3` 要求不要两份实现）。
  /// `clearable: false` —— 详情面板的写路径（`Task.copyWith`）没法把字段写回 null。
  Widget _dateRow(
    BuildContext context, {
    required String rowKey,
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
  }) {
    return ComposeDateTimeRow(
      rowKey: rowKey,
      label: label,
      height: 36,
      clearable: false,
      helpText: '$label日期',
      value: value,
      pickDate: pickDate,
      pickTime: pickTime,
      onChanged: onChanged,
    );
  }
}

/// 值区域统一包一层弹出菜单（点击弹下拉）。
class _AttrPopup<T> extends StatelessWidget {
  const _AttrPopup({
    required this.value,
    required this.items,
    required this.onSelected,
    required this.child,
  });

  final T? value;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T?> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      initialValue: value,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (BuildContext context) => items,
      child: child,
    );
  }
}
