import 'package:flutter/material.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/tasks/task_checkbox.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 子任务区（F5，自 detail_sections.dart 拆出）：行 32dp（16dp 勾选 + 14sp），
/// 头部「子任务 · n/m」。
class DetailSubtasks extends StatelessWidget {
  const DetailSubtasks({
    super.key,
    required this.subtasks,
    required this.onToggle,
    required this.onAdd,
    required this.onDelete,
  });

  final List<Subtask> subtasks;
  final ValueChanged<Subtask> onToggle;
  final ValueChanged<String> onAdd;
  final ValueChanged<Subtask> onDelete;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final int done = subtasks.where((Subtask s) => s.completed).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('子任务',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary)),
            const SizedBox(width: AppDimens.s8),
            if (subtasks.isNotEmpty)
              Text('$done/${subtasks.length}',
                  style: TextStyle(fontSize: 12, color: colors.textFaint)),
          ],
        ),
        const SizedBox(height: AppDimens.s4),
        for (final Subtask s in subtasks)
          _SubtaskRow(
            subtask: s,
            onToggle: () => onToggle(s),
            onDelete: () => onDelete(s),
          ),
        _AddSubtaskField(onAdd: onAdd),
      ],
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({
    required this.subtask,
    required this.onToggle,
    required this.onDelete,
  });

  final Subtask subtask;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return SizedBox(
      height: 32,
      child: Row(
        children: <Widget>[
          SubtaskCheckbox(
            completed: subtask.completed,
            onToggle: onToggle,
          ),
          const SizedBox(width: AppDimens.s8),
          Expanded(
            child: Text(
              subtask.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: subtask.completed ? colors.textSecondary : null,
                decoration:
                    subtask.completed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          InkWell(
            onTap: onDelete,
            child: Icon(Icons.close, size: 14, color: colors.textFaint),
          ),
        ],
      ),
    );
  }
}

class _AddSubtaskField extends StatefulWidget {
  const _AddSubtaskField({required this.onAdd});

  final ValueChanged<String> onAdd;

  @override
  State<_AddSubtaskField> createState() => _AddSubtaskFieldState();
}

class _AddSubtaskFieldState extends State<_AddSubtaskField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onAdd(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return SizedBox(
      height: 32,
      child: Row(
        children: <Widget>[
          Icon(Icons.add, size: 16, color: colors.textFaint),
          const SizedBox(width: AppDimens.s8),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '添加子任务，回车保存',
                hintStyle: TextStyle(color: colors.textFaint, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
