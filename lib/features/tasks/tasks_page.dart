import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/chaoxing/chaoxing_due_banner.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/list_sheet.dart';
import 'package:qingdan/features/tasks/task_list_pane.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/features/tasks/trash_pane.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 清单页（M5 定案第 4 条，仅窄屏形态使用）。
///
/// 抽屉下线后，原来一屏侧栏里的东西被拆成三处：
/// 「哪个清单」→ 左上「清单 ▾」半屏面板；「看哪个时间视图」→ 顶部分段 chips；
/// 「回收站」→ 右上 ⋮。`TaskListPane` 本体逻辑一行不动，只是不再自绘标题行
/// （`showHeader: false`），避免页标题 + 同步图标在顶栏与页内各来一遍。
class TasksPage extends StatelessWidget {
  const TasksPage({super.key, this.onOpenDetailPage});

  final VoidCallback? onOpenDetailPage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _TasksBar(),
        Consumer<TaskPaneModel>(
          builder: (BuildContext _, TaskPaneModel model, _) =>
              model.viewId == kSmartToday
                  ? const ChaoxingDueBanner()
                  : const SizedBox.shrink(),
        ),
        Expanded(
          child: Consumer<TaskPaneModel>(
            builder: (BuildContext _, TaskPaneModel model, _) =>
                model.viewId == kTrash
                    ? const TrashPane()
                    : TaskListPane(
                        showHeader: false,
                        onOpenDetailPage: onOpenDetailPage),
          ),
        ),
      ],
    );
  }
}

/// 页头两行：清单切换 + 排序/回收站，下面一行时间视图 chips。
class _TasksBar extends StatelessWidget {
  const _TasksBar();

  @override
  Widget build(BuildContext context) {
    final TaskPaneModel model = context.watch<TaskPaneModel>();
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(AppDimens.listPanePaddingH,
              AppDimens.s8, AppDimens.listPanePaddingH, 0),
          child: Row(
            children: <Widget>[
              const _ListSwitcherButton(),
              const Spacer(),
              if (model.isUserList && model.viewId != kTrash)
                _SortMenu(model: model),
              const _MoreMenu(),
            ],
          ),
        ),
        const _ViewChips(),
      ],
    );
  }
}

/// 左上「清单 ▾」：点开半屏面板切换 / 新建 / 重命名 / 删除。
class _ListSwitcherButton extends StatelessWidget {
  const _ListSwitcherButton();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppDimens.radiusMobile),
      onTap: () => showListSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.s8, vertical: AppDimens.s8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('清单',
                key: const ValueKey<String>('listSwitcher'),
                style: AppTypography.body
                    .copyWith(color: colors.textPrimary)),
            Icon(Icons.expand_more, size: 18, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// 时间视图 chips（今天 / 最近 7 天 / 所有 / 已完成）+ 未完成计数。
/// 横向可滚：411dp 下加长文案或大字号都不该把行撑爆（M4a S4b 的教训）。
class _ViewChips extends StatelessWidget {
  const _ViewChips();

  @override
  Widget build(BuildContext context) {
    final SidebarModel sidebar = context.watch<SidebarModel>();
    final List<_ChipSpec> specs = <_ChipSpec>[
      _ChipSpec('今天', kSmartToday, sidebar.todayCount),
      _ChipSpec('最近 7 天', kSmartNext7, sidebar.next7Count),
      _ChipSpec('所有', kSmartAll, sidebar.allCount),
      _ChipSpec('已完成', kSmartCompleted, sidebar.completedCount),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(AppDimens.listPanePaddingH,
          AppDimens.s8, AppDimens.listPanePaddingH, AppDimens.s4),
      child: Row(
        children: <Widget>[
          for (final _ChipSpec spec in specs) ...<Widget>[
            ChoiceChip(
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              selected: sidebar.selectedId == spec.id,
              onSelected: (bool _) => sidebar.select(spec.id),
              label: Text(
                spec.count > 0 ? '${spec.label} ${spec.count}' : spec.label,
                key: ValueKey<String>('chip:${spec.id}'),
                style: AppTypography.meta,
              ),
            ),
            const SizedBox(width: AppDimens.s8),
          ],
        ],
      ),
    );
  }
}

class _ChipSpec {
  const _ChipSpec(this.label, this.id, this.count);

  final String label;
  final String id;
  final int count;
}

/// 排序（F9）：用户清单才有手动排序四档，从 `TaskListPane` 的标题行搬来。
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.model});

  final TaskPaneModel model;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TaskSortMode>(
      tooltip: '排序',
      icon: const Icon(Icons.sort, size: 20),
      onSelected: model.setSortMode,
      itemBuilder: (BuildContext _) => const <PopupMenuEntry<TaskSortMode>>[
        PopupMenuItem<TaskSortMode>(value: TaskSortMode.manual, child: Text('手动排序')),
        PopupMenuItem<TaskSortMode>(value: TaskSortMode.due, child: Text('按到期时间')),
        PopupMenuItem<TaskSortMode>(
            value: TaskSortMode.priority, child: Text('按优先级')),
        PopupMenuItem<TaskSortMode>(value: TaskSortMode.title, child: Text('按标题')),
      ],
    );
  }
}

/// 右上 ⋮：回收站（M5 定案第 4 条）。
class _MoreMenu extends StatelessWidget {
  const _MoreMenu();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return PopupMenuButton<String>(
      tooltip: '更多',
      iconSize: 20,
      color: colors.surface,
      icon: Icon(Icons.more_vert, size: 20, color: colors.textSecondary),
      onSelected: (String _) =>
          context.read<SidebarModel>().select(kTrash),
      itemBuilder: (BuildContext _) => const <PopupMenuItem<String>>[
        PopupMenuItem<String>(
            value: 'trash',
            child: Text('回收站', key: ValueKey<String>('menuTrash'))),
      ],
    );
  }
}
