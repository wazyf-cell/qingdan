import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/list_shortcuts.dart';
import 'package:qingdan/features/tasks/quick_add_field.dart';
import 'package:qingdan/features/tasks/task_list_body.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/features/tasks/task_row.dart';
import 'package:qingdan/features/shell/sidebar/sync_status_model.dart';
import 'package:qingdan/sync/sync_status.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 列表区（F1 快速添加 + F9 排序 + 任务行列表 + 空状态 + §3.4 快捷键）。
class TaskListPane extends StatelessWidget {
  const TaskListPane(
      {super.key, this.onOpenDetailPage, this.showHeader = true});

  /// 窄屏形态（<720dp）详情不是内嵌面板：点行后由外层壳推全屏详情页。
  final VoidCallback? onOpenDetailPage;

  /// 标题行（视图名 + 手动同步 + 排序）。清单页（M5）自带页头两行，这里关掉，
  /// 否则同步图标在 56dp 顶栏与页内各出现一次。
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return ListShortcuts(
      child: Consumer<TaskPaneModel>(builder: (
        BuildContext context,
        TaskPaneModel model,
        _,
      ) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (showHeader) _PaneHeader(model: model),
            Padding(
              padding: EdgeInsets.fromLTRB(AppDimens.listPanePaddingH,
                  showHeader ? 0 : AppDimens.s8, AppDimens.listPanePaddingH, 0),
              child: QuickAddField(model: model),
            ),
            const SizedBox(height: AppDimens.s4),
            Expanded(
              child: TaskListBody(
                rows: model.tasks,
                groupHeaders: _groupHeaders(model),
                reorderable: model.isUserList &&
                    model.sortMode == TaskSortMode.manual,
                onReorder: model.reorderManual,
                emptyState: _EmptyState(viewId: model.viewId),
                buildRow: (BuildContext context, Task task, int index) {
                  if (model.collapsing.contains(task.id)) {
                    return const CollapsingRow();
                  }
                  return TaskRow(
                    key: ValueKey<String>(task.id),
                    index: index,
                    task: task,
                    lists: model.lists,
                    subtaskProgress: model.subtaskProgress[task.id],
                    tagCount: model.tagCounts[task.id] ?? 0,
                    selected: model.selectedTaskId == task.id,
                    showDragHandle: model.isUserList &&
                        model.sortMode == TaskSortMode.manual,
                    onToggle: () => model.toggleComplete(task),
                    onOpenDetail: () {
                      model.openDetail(task.id);
                      onOpenDetailPage?.call();
                    },
                    onDelete: () => _deleteWithUndo(context, model, task),
                    onEditDate: () => _pickDate(context, model, task),
                    onChangePriority: (TaskPriority p) =>
                        model.setPriority(task, p),
                    onCopyAsText: () => _copyAsText(context, task),
                    onMoveToList: (String? listId) =>
                        model.moveToList(task, listId),
                    onRestore: () {},
                    onDeleteForever: () {},
                  );
                },
              ),
            ),
          ],
        );
      }),
    );
  }

  /// 智能清单（今天/最近7天）按日期分组：已过期/今天/明天/以后。
  static List<String?> _groupHeaders(TaskPaneModel model) {
    final bool smart =
        model.viewId == kSmartToday || model.viewId == kSmartNext7;
    if (!smart) return List<String?>.filled(model.tasks.length, null);
    final DateTime now = DateTime.now();
    final DateTime today =
        DateTime(now.year, now.month, now.day);
    String? headerFor(Task t) {
      final DateTime? due = t.dueDate?.toLocal();
      if (due == null) return null;
      final DateTime day = DateTime(due.year, due.month, due.day);
      if (day.isBefore(today)) return '已过期';
      if (day == today) return '今天';
      if (day == today.add(const Duration(days: 1))) return '明天';
      return '以后';
    }

    final List<String?> headers = <String?>[];
    String? last;
    for (final Task t in model.tasks) {
      final String? h = headerFor(t);
      headers.add(h == last ? null : h);
      last = h;
    }
    return headers;
  }

  static void _deleteWithUndo(
      BuildContext context, TaskPaneModel model, Task task) {
    model.deleteTask(task).then((String title) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除「$title」'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => model.undoDelete(task.id),
          ),
        ),
      );
    });
  }

  static Future<void> _pickDate(
      BuildContext context, TaskPaneModel model, Task task) async {
    final DateTime initial =
        task.dueDate?.toLocal() ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 5),
    );
    if (picked != null) {
      await model.setDueDate(task, picked);
    }
  }

  static void _copyAsText(BuildContext context, Task task) {
    final StringBuffer buf = StringBuffer(task.title);
    if (task.note.isNotEmpty) {
      buf.write('\n${task.note}');
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制为文本'), duration: Duration(seconds: 2)),
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.model});

  final TaskPaneModel model;

  @override
  Widget build(BuildContext context) {
    // §2.6：<720dp 时页标题归 56dp 顶栏（移动 17sp），本行只留操作按钮，
    // 否则同一清单名会在顶栏与标题行各渲染一次。
    final bool titleInTopBar =
        MediaQuery.sizeOf(context).width < AppDimens.breakpointNarrow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDimens.listPanePaddingH,
          AppDimens.s12, AppDimens.s8, AppDimens.s8),
      child: Row(
        children: <Widget>[
          if (titleInTopBar)
            const Spacer()
          else
            Expanded(
                child: Text(model.currentViewName,
                    key: const ValueKey<String>('paneTitle'),
                    style: AppTypography.pageTitle)),
          // M3 §5.4：标题行右端手动同步图标（同步中禁用置灰）。未装配
          // SyncStatusModel（如测试）时不渲染，保持既有布局。
          if (context.watch<SyncStatusModel?>() != null)
            _ManualSyncButton(model: context.watch<SyncStatusModel>()),
          if (model.isUserList)
            PopupMenuButton<TaskSortMode>(
              tooltip: '排序',
              icon: const Icon(Icons.sort, size: 20),
              onSelected: model.setSortMode,
              itemBuilder: (BuildContext context) => const <PopupMenuEntry<TaskSortMode>>[
                PopupMenuItem<TaskSortMode>(
                    value: TaskSortMode.manual, child: Text('手动排序')),
                PopupMenuItem<TaskSortMode>(
                    value: TaskSortMode.due, child: Text('按到期时间')),
                PopupMenuItem<TaskSortMode>(
                    value: TaskSortMode.priority, child: Text('按优先级')),
                PopupMenuItem<TaskSortMode>(
                    value: TaskSortMode.title, child: Text('按标题')),
              ],
            ),
        ],
      ),
    );
  }
}

/// 手动同步按钮（§5.4）：24dp 图标位，点击即 syncNow；同步中禁用置灰。
/// 触控热区扩到 ≥44dp（移动端）。
class _ManualSyncButton extends StatelessWidget {
  const _ManualSyncButton({required this.model});

  final SyncStatusModel model;

  @override
  Widget build(BuildContext context) {
    final bool busy = model.status.kind == SyncStatusKind.running;
    return Tooltip(
      message: '立即同步',
      child: IconButton(
        onPressed: busy ? null : model.syncNow,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(
          busy ? Icons.sync : Icons.sync_outlined,
          size: 20,
          color: busy
              ? AppColors.of(context).accent
              : AppColors.of(context).textSecondary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.viewId});

  final String viewId;

  @override
  Widget build(BuildContext context) {
    final Color faint = Theme.of(context).colorScheme.outline;
    final Widget icon =
        Icon(Icons.check_circle_outline, size: 48, color: faint);
    if (viewId == kSmartToday) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            icon,
            const SizedBox(height: AppDimens.s12),
            Text('今天没有安排', style: TextStyle(color: faint)),
            const SizedBox(height: AppDimens.s4),
            GestureDetector(
              onTap: () =>
                  context.read<SidebarModel>().select(kSmartNext7),
              child: Text('看看最近 7 天 →',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary)),
            ),
          ],
        ),
      );
    }
    if (viewId == kSmartCompleted) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            icon,
            const SizedBox(height: AppDimens.s12),
            Text('还没有完成的任务', style: TextStyle(color: faint)),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          icon,
          const SizedBox(height: AppDimens.s12),
          Text('这个清单还没有任务', style: TextStyle(color: faint)),
          const SizedBox(height: AppDimens.s4),
          Text('在上方输入框添加，回车保存', style: TextStyle(color: faint, fontSize: 12)),
        ],
      ),
    );
  }
}
