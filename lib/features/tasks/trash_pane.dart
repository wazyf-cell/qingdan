import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/task_use_case.dart';
import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/features/tasks/task_row.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 回收站（F4，§2.5）：顶部「清空回收站」+「30 天后自动清除」，
/// 行复用 TaskRow（restoreMode），恢复 / 彻底删除，彻底删除需确认。
class TrashPane extends StatefulWidget {
  const TrashPane({super.key});

  @override
  State<TrashPane> createState() => _TrashPaneState();
}

class _TrashPaneState extends State<TrashPane> {
  List<Task> _trashed = <Task>[];
  bool _loaded = false;

  TaskUseCase? get _useCase => context.read<TaskPaneModel>().useCase;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Task> trashed =
        await _useCase?.findTrashed() ?? <Task>[];
    if (!mounted) return;
    setState(() {
      _trashed = trashed;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(AppDimens.listPanePaddingH,
              AppDimens.s12, AppDimens.s8, AppDimens.s8),
          child: Row(
            children: <Widget>[
              // §2.6：<720dp 时页标题归 56dp 顶栏，本工具行只留操作项，
              // 否则「回收站」会在顶栏与工具行各渲染一次。
              if (MediaQuery.sizeOf(context).width <
                  AppDimens.breakpointNarrow)
                const Spacer()
              else
                Expanded(
                  child: Text('回收站',
                      key: const ValueKey<String>('paneTitle'),
                      style: AppTypography.pageTitle),
                ),
              GestureDetector(
                onTap: _trashed.isEmpty ? null : _emptyTrash,
                child: Text('清空回收站',
                    style: TextStyle(
                        fontSize: 13,
                        color: _trashed.isEmpty
                            ? colors.textFaint
                            : colors.overdue)),
              ),
            ],
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppDimens.listPanePaddingH),
          child: Text('30 天后自动清除',
              style: TextStyle(fontSize: 12, color: colors.textFaint)),
        ),
        const SizedBox(height: AppDimens.s4),
        Expanded(child: _buildList(context)),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    if (!_loaded) return const SizedBox.expand();
    if (_trashed.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.delete_outline,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: AppDimens.s12),
            Text('回收站是空的',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _trashed.length,
      itemBuilder: (BuildContext context, int index) {
        final Task task = _trashed[index];
        return TaskRow(
          key: ValueKey<String>(task.id),
          index: index,
          task: task,
          restoreMode: true,
          onToggle: () {},
          onOpenDetail: () {},
          onDelete: () {},
          onRestore: () => _restore(task),
          onDeleteForever: () => _deleteForever(task),
          onChangePriority: (_) {},
          onEditDate: () {},
          onCopyAsText: () {},
          onMoveToList: (_) {},
        );
      },
    );
  }

  Future<void> _restore(Task task) async {
    await _useCase?.restore(task.id);
    if (!mounted) return;
    context.read<SidebarModel>().load();
    await _reload();
  }

  Future<void> _deleteForever(Task task) async {
    final bool? confirmed = await _confirm(
      context,
      title: '彻底删除任务？',
      body: '「${task.title}」将被永久删除，此操作无法撤销。',
      actionLabel: '彻底删除',
    );
    if (confirmed != true) return;
    await _useCase?.deleteForever(task.id);
    await _reload();
  }

  Future<void> _emptyTrash() async {
    final bool? confirmed = await _confirm(
      context,
      title: '清空回收站？',
      body: '回收站中的全部任务将被永久删除，此操作无法撤销。',
      actionLabel: '清空回收站',
    );
    if (confirmed != true) return;
    await _useCase?.emptyTrash();
    await _reload();
  }

  static Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String actionLabel,
  }) {
    final AppColors colors = AppColors.of(context);
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(body, style: const TextStyle(fontSize: 14)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: colors.overdue,
                foregroundColor: Colors.white),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
