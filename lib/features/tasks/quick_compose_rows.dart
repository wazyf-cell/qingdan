// 快捷抽屉的两类选择行：清单 / 优先级（自 quick_compose_sheet.dart 拆出，保持
// 单文件不超 300 行）。视觉规格沿用详情面板属性行（标签 12sp、行高 44dp 触控）。
// 日期行在 compose_date_time_row.dart（抽屉与详情面板共用）。

import 'package:flutter/material.dart';

import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/features/tasks/due_format.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 一行：左标签 + 右内容（标签 12sp、值区左对齐）。
///
/// 抽屉里的行高 44dp（§2.6 触控下限），详情面板沿用 36dp，所以高度做成参数。
class ComposeRow extends StatelessWidget {
  const ComposeRow({
    super.key,
    required this.label,
    required this.child,
    this.height = 44,
  });

  final String label;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline)),
          ),
          Expanded(
              child: Align(alignment: Alignment.centerLeft, child: child)),
        ],
      ),
    );
  }
}

class ComposeListRow extends StatelessWidget {
  const ComposeListRow({
    super.key,
    required this.lists,
    required this.value,
    required this.onChanged,
  });

  final List<TaskList> lists;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    String name = '收集箱';
    for (final TaskList list in lists) {
      if (list.id == value) name = list.name;
    }
    return ComposeRow(
      label: '清单',
      child: PopupMenuButton<String>(
        key: const ValueKey<String>('compose-list'),
        initialValue: value ?? '',
        padding: EdgeInsets.zero,
        onSelected: (String v) => onChanged(v.isEmpty ? null : v),
        itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
              value: '', child: Text('收集箱', style: TextStyle(fontSize: 14))),
          for (final TaskList list in lists)
            PopupMenuItem<String>(
                value: list.id,
                child: Text(list.name, style: const TextStyle(fontSize: 14))),
        ],
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(name, style: const TextStyle(fontSize: 14)),
          const Icon(Icons.expand_more, size: 18),
        ]),
      ),
    );
  }
}

class ComposePriorityRow extends StatelessWidget {
  const ComposePriorityRow({super.key, required this.value, required this.onChanged});

  final TaskPriority value;
  final ValueChanged<TaskPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color? color = priorityColor(value, colors);
    return ComposeRow(
      label: '优先级',
      child: PopupMenuButton<TaskPriority>(
        key: const ValueKey<String>('compose-priority'),
        initialValue: value,
        padding: EdgeInsets.zero,
        onSelected: onChanged,
        itemBuilder: (BuildContext _) => <PopupMenuEntry<TaskPriority>>[
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
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (color != null)
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(1.5)),
            ),
          if (color != null) const SizedBox(width: AppDimens.s8),
          Text(priorityLabel(value), style: const TextStyle(fontSize: 14)),
          const Icon(Icons.expand_more, size: 18),
        ]),
      ),
    );
  }
}

