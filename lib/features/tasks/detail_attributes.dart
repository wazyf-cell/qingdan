import 'package:flutter/material.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/features/tasks/due_format.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 详情面板属性行（§2.3）：清单 / 优先级 / 开始 / 结束，每行 36dp，
/// 标签 12sp 次要文字 + 值 14sp。移动形态下由 [DetailAttributes.grid] 走 2 列。
class DetailAttributes extends StatelessWidget {
  const DetailAttributes({
    super.key,
    required this.task,
    required this.lists,
    required this.onPickList,
    required this.onPickPriority,
    required this.onPickStartDate,
    required this.onPickEndDate,
    this.twoColumns = false,
  });

  final Task task;
  final List<TaskList> lists;
  final ValueChanged<String?> onPickList;
  final ValueChanged<TaskPriority> onPickPriority;
  final ValueChanged<DateTime?> onPickStartDate;
  final ValueChanged<DateTime?> onPickEndDate;
  final bool twoColumns;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[
      _listRow(context),
      _priorityRow(context),
      _dateRow(
        context,
        label: '开始',
        value: task.startDate?.toLocal(),
        onPick: onPickStartDate,
      ),
      _dateRow(
        context,
        label: '结束',
        value: task.endDate?.toLocal(),
        onPick: onPickEndDate,
      ),
    ];
    if (!twoColumns) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }
    return Column(
      children: <Widget>[
        for (int i = 0; i < rows.length; i += 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: rows[i]),
              if (i + 1 < rows.length) Expanded(child: rows[i + 1]),
            ],
          ),
      ],
    );
  }

  Widget _listRow(BuildContext context) {
    String name = '收集箱';
    for (final TaskList list in lists) {
      if (list.id == task.listId) name = list.name;
    }
    return _AttrRow(
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
    return _AttrRow(
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

  Widget _dateRow(
    BuildContext context, {
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onPick,
  }) {
    final String text = value == null
        ? '设置日期'
        : '${value.year}/${value.month}/${value.day}';
    return _AttrRow(
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
        onTap: () async {
          final DateTime initial = value ?? DateTime.now();
          final DateTime? picked = await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: DateTime(initial.year - 5),
            lastDate: DateTime(initial.year + 5),
          );
          if (picked != null) onPick(picked);
        },
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: value == null
                ? Theme.of(context).colorScheme.outline
                : null,
          ),
        ),
      ),
    );
  }
}

class _AttrRow extends StatelessWidget {
  const _AttrRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline)),
          ),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: child)),
        ],
      ),
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
