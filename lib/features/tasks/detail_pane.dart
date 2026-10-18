import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/task_use_case.dart';
import 'package:qingdan/domain/tag.dart';
import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/tasks/detail_attributes.dart';
import 'package:qingdan/features/tasks/detail_sections.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 详情编辑面板（F2，§2.3）：标题 / 属性 / 标签 / 备注 / 子任务 / 底部。
/// 所有编辑即时生效（无保存按钮）。
class DetailPane extends StatefulWidget {
  const DetailPane({super.key, this.twoColumns = false});

  /// 移动形态（<720dp 全屏页）：属性行 2 列网格。
  final bool twoColumns;

  @override
  State<DetailPane> createState() => _DetailPaneState();
}

class _DetailPaneState extends State<DetailPane> {
  Task? _loaded;
  List<Subtask> _subtasks = <Subtask>[];
  List<Tag> _tags = <Tag>[];
  late final TextEditingController _title;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  TaskPaneModel get _model => context.read<TaskPaneModel>();

  Future<void> _load(Task task) async {
    final TaskUseCase? useCase = _model.useCase;
    if (useCase == null) return;
    final List<Subtask> subs = await useCase.findSubtasks(task.id);
    final List<Tag> tags = await useCase.findTagsOf(task.id);
    if (!mounted) return;
    setState(() {
      _loaded = task;
      _subtasks = subs;
      _tags = tags;
      _title.text = task.title;
      _note.text = task.note;
    });
  }

  Future<void> _update(Task task, Task Function(Task) transform) async {
    final TaskUseCase? useCase = _model.useCase;
    if (useCase == null) return;
    await useCase.update(transform(task));
    await _model.load();
  }

  Future<void> _refreshSubtasks(String taskId) async {
    final TaskUseCase? useCase = _model.useCase;
    if (useCase == null) return;
    final List<Subtask> subs = await useCase.findSubtasks(taskId);
    if (!mounted) return;
    setState(() => _subtasks = subs);
    await _model.load();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskPaneModel>(
      builder: (BuildContext context, TaskPaneModel model, _) {
        Task? task;
        for (final Task t in model.tasks) {
          if (t.id == model.detailTaskId) {
            task = t;
            break;
          }
        }
        if (task == null) {
          return const Center(
            child: Text('选择一个任务查看详情', style: TextStyle(fontSize: 13)),
          );
        }
        if (_loaded?.id != task.id) {
          _load(task);
          return const SizedBox.expand();
        }
        return _buildBody(context, task);
      },
    );
  }

  Widget _buildBody(BuildContext context, Task task) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimens.panelPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _title,
            maxLines: null,
            style: AppTypography.panelTitle,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (String v) => _update(
                task, (Task t) => t.copyWith(title: v.trim())),
          ),
          const SizedBox(height: AppDimens.s12),
          DetailAttributes(
            task: task,
            lists: _model.lists,
            twoColumns: widget.twoColumns,
            onPickList: (String? listId) =>
                _update(task, (Task t) => t.copyWith(listId: listId)),
            onPickPriority: (p) =>
                _update(task, (Task t) => t.copyWith(priority: p)),
            onPickStartDate: (DateTime? d) => _update(
                task,
                (Task t) => t.copyWith(
                    startDate: d == null ? t.startDate : d.toUtc())),
            onPickEndDate: (DateTime? d) => _update(
                task,
                (Task t) =>
                    t.copyWith(endDate: d == null ? t.endDate : d.toUtc())),
          ),
          const SizedBox(height: AppDimens.s12),
          DetailTags(
            tags: _tags,
            onAdd: () => _addTag(task),
            onRemove: (Tag tag) async {
              await _model.useCase?.detachTag(taskId: task.id, tagId: tag.id);
              await _load(task);
            },
          ),
          const SizedBox(height: AppDimens.s16),
          DetailNotes(
            controller: _note,
            onChanged: () => _scheduleNoteSave(task),
          ),
          const SizedBox(height: AppDimens.s16),
          DetailSubtasks(
            subtasks: _subtasks,
            onToggle: (Subtask s) async {
              await _model.useCase
                  ?.setSubtaskCompleted(s, !s.completed);
              await _refreshSubtasks(task.id);
            },
            onAdd: (String title) async {
              await _model.useCase?.addSubtask(
                taskId: task.id,
                title: title,
                sortOrder: _subtasks.length,
              );
              await _refreshSubtasks(task.id);
            },
            onDelete: (Subtask s) async {
              await _model.useCase?.deleteSubtask(s.id);
              await _refreshSubtasks(task.id);
            },
          ),
          const SizedBox(height: AppDimens.s24),
          _Footer(task: task, onDelete: () => _deleteTask(task)),
        ],
      ),
    );
  }

  Timer? _noteTimer;
  String _lastNoteSaved = '';

  void _scheduleNoteSave(Task task) {
    _noteTimer?.cancel();
    _noteTimer = Timer(const Duration(milliseconds: 600), () {
      final String text = _note.text;
      if (text == _lastNoteSaved) return;
      _lastNoteSaved = text;
      _update(task, (Task t) => t.copyWith(note: text));
    });
  }

  Future<void> _addTag(Task task) async {
    final TaskUseCase? useCase = _model.useCase;
    if (useCase == null) return;
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('添加标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '标签名称'),
          onSubmitted: (String v) => Navigator.of(context).pop(v),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('添加')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final List<Tag> all = await useCase.findAllTags();
    Tag? tag;
    for (final Tag t in all) {
      if (t.name == name) tag = t;
    }
    tag ??= await useCase.createTag(name);
    await useCase.attachTag(taskId: task.id, tagId: tag.id);
    await _load(task);
  }

  Future<void> _deleteTask(Task task) async {
    await _model.deleteTask(task);
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.task, required this.onDelete});

  final Task task;
  final VoidCallback onDelete;

  String _fmt(DateTime? utc) {
    if (utc == null) return '—';
    final DateTime local = utc.toLocal();
    return '${local.year}/${local.month}/${local.day} ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '创建于 ${_fmt(task.createdTime)}'
            '${task.completedTime != null ? ' · 完成 ${_fmt(task.completedTime)}' : ''}',
            style: TextStyle(fontSize: 12, color: colors.textFaint),
          ),
        ),
        GestureDetector(
          onTap: onDelete,
          child: Text('删除',
              style: TextStyle(fontSize: 13, color: colors.overdue)),
        ),
      ],
    );
  }
}
