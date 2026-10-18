import 'package:flutter/material.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'due_format.dart';
import 'task_checkbox.dart';
import 'task_row_menu.dart';

/// 任务行（§2.1，40dp）：勾选框 18 → 优先级竖条 3×20 → 标题 flex（来源圆点
/// 预留 6dp 位）→ 元信息（◐n/m · 标签数 · 到期）。
///
/// 完成态：标题加删除线并过渡到次要文字色（150ms 线性，§3.1），
/// 行保持在原位不沉底。回收站形态：勾选框位替换为 20dp 恢复图标，
/// 标题次要文字色，[restoreMode] 为 true。
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onOpenDetail,
    required this.onDelete,
    required this.onRestore,
    required this.onDeleteForever,
    required this.onChangePriority,
    required this.onEditDate,
    required this.onCopyAsText,
    required this.onMoveToList,
    this.subtaskProgress,
    this.tagCount,
    this.restoreMode = false,
    this.selected = false,
    this.showDragHandle = false,
    this.onReorder,
    this.index = 0,
    this.lists = const <TaskList>[],
  });

  final Task task;
  final List<TaskList> lists;

  /// 在列表中的位置（拖拽柄 [ReorderableDragStartListener] 需要）。
  final int index;
  final VoidCallback onToggle;
  final VoidCallback onOpenDetail;
  final VoidCallback onDelete;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;
  final ValueChanged<TaskPriority> onChangePriority;
  final VoidCallback onEditDate;
  final VoidCallback onCopyAsText;
  final ValueChanged<String> onMoveToList;
  final List<int>? subtaskProgress; // [完成数, 总数]
  final int? tagCount;
  final bool restoreMode;
  final bool selected;
  final bool showDragHandle;
  final VoidCallback? onReorder;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final (String? dueText, bool overdue) =
        formatDueText(task.dueDate, completed: task.completed);
    final Color titleColor = restoreMode || task.completed
        ? colors.textSecondary
        : colors.textPrimary;

    final Widget row = SizedBox(
      height: AppDimens.taskRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.listPanePaddingH),
        child: Row(
          children: <Widget>[
            // 拖拽柄（§3.2：仅手动排序 hover 出现 16dp 六点柄）。
            SizedBox(
              width: 16,
              child: showDragHandle
                  ? MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: ReorderableDragStartListener(
                        index: index,
                        child: Icon(Icons.drag_indicator,
                            size: 16, color: colors.textFaint),
                      ),
                    )
                  : null,
            ),
            // 勾选框 / 回收站恢复图标（20dp）。
            SizedBox(
              width: 26,
              child: Center(
                child: restoreMode
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 20, minHeight: 20),
                        icon: Icon(Icons.restore,
                            size: 20, color: colors.textSecondary),
                        tooltip: '恢复',
                        onPressed: onRestore,
                      )
                    : TaskCheckbox(
                        completed: task.completed,
                        onToggle: onToggle,
                      ),
              ),
            ),
            const SizedBox(width: AppDimens.s8),
            // 优先级竖条 3×20dp（无优先级空 3dp 占位，§2.1）。
            Container(
              width: 3,
              height: 20,
              margin: const EdgeInsets.only(right: AppDimens.s8),
              color: restoreMode
                  ? null
                  : priorityColor(task.priority, colors),
            ),
            // 来源圆点预留位（§2.1：标题前 6dp；M1 无事件/课表数据，恒空）。
            const SizedBox(width: 6),
            Expanded(
              child: _AnimatedTitle(
                text: task.title,
                color: titleColor,
                strike: task.completed && !restoreMode,
              ),
            ),
            _MetaInfo(
              task: task,
              dueText: dueText,
              overdue: overdue,
              subtaskProgress: subtaskProgress,
              tagCount: tagCount,
              colors: colors,
            ),
          ],
        ),
      ),
    );

    return InkWell(
      onTap: onOpenDetail,
      onSecondaryTapUp: (TapUpDetails d) => _showMenu(context, d.globalPosition),
      onLongPress: () => _showMenuAtCenter(context),
      hoverColor: colors.surfaceHigh,
      child: Container(
        color: selected ? colors.accentFaint : Colors.transparent,
        child: row,
      ),
    );
  }

  void _showMenu(BuildContext context, Offset position) {
    showTaskRowMenu(
      context,
      position,
      task: task,
      restoreMode: restoreMode,
      lists: lists,
      onOpenDetail: onOpenDetail,
      onDelete: onDelete,
      onRestore: onRestore,
      onDeleteForever: onDeleteForever,
      onChangePriority: onChangePriority,
      onEditDate: onEditDate,
      onCopyAsText: onCopyAsText,
      onMoveToList: onMoveToList,
    );
  }

  void _showMenuAtCenter(BuildContext context) {
    final RenderBox box =
        context.findRenderObject()! as RenderBox;
    _showMenu(context, box.localToGlobal(Offset.zero));
  }
}

/// 标题：删除线与颜色 150ms 线性过渡（§3.1），不做位移/飘落/发光。
class _AnimatedTitle extends StatelessWidget {
  const _AnimatedTitle({
    required this.text,
    required this.color,
    required this.strike,
  });

  final String text;
  final Color color;
  final bool strike;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: strike ? 0 : 1, end: strike ? 1 : 0),
      duration: const Duration(milliseconds: 150),
      curve: Curves.linear,
      builder: (BuildContext context, double t, _) {
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.body.copyWith(
            // 颜色随 t 向次要文字色线性过渡（§3.1：150ms）。
            color: Color.lerp(color, colors.textSecondary, t)!,
            decoration:
                strike || t > 0 ? TextDecoration.lineThrough : TextDecoration.none,
            decorationColor: Color.lerp(color, colors.textSecondary, t),
            decorationThickness: 1.2,
          ),
        );
      },
    );
  }
}

/// 元信息区（§2.1 右对齐）：子任务进度 ◐n/m、标签数、重复图标（12dp 预留）、
/// 到期时间（过期整段用过期色）。
class _MetaInfo extends StatelessWidget {
  const _MetaInfo({
    required this.task,
    required this.dueText,
    required this.overdue,
    required this.subtaskProgress,
    required this.tagCount,
    required this.colors,
  });

  final Task task;
  final String? dueText;
  final bool overdue;
  final List<int>? subtaskProgress;
  final int? tagCount;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final TextStyle meta = AppTypography.meta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (subtaskProgress != null) ...<Widget>[
          Icon(Icons.schedule, size: 12, color: colors.textFaint),
          const SizedBox(width: 2),
          Text('${subtaskProgress![0]}/${subtaskProgress![1]}',
              style: meta.copyWith(color: colors.textSecondary)),
          const SizedBox(width: AppDimens.s8),
        ],
        if (tagCount != null) ...<Widget>[
          Icon(Icons.label_outline, size: 12, color: colors.textFaint),
          const SizedBox(width: 2),
          Text('$tagCount',
              style: meta.copyWith(color: colors.textSecondary)),
          const SizedBox(width: AppDimens.s8),
        ],
        // 重复任务循环图标（§2.1：M1 无数据，结构预留 12dp 位）。
        const SizedBox(width: 12),
        if (dueText != null)
          Text(dueText!,
              style: meta.copyWith(
                  color: overdue ? colors.overdue : colors.textSecondary)),
      ],
    );
  }
}
