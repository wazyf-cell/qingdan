import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/list_actions.dart';
import 'package:qingdan/features/tasks/list_sheet.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 清单页页头两行（M6-A2）。
///
/// 上排：三个图标按钮 —— 清单列表 / 添加清单 / 回收站（取代原「清单 ▾ + 排序 + ⋮」）。
/// 下排：时间视图 chips，行尾挂排序入口（M6-A2 从标题行搬来）。
///
/// 三个按钮只用图标 + tooltip，不带文字标签：页标题在上一层的 56dp 顶栏
/// （`mobile_top_bar.dart` 的 `topBarTitle`），本页任何加宽都会把标题挤到换行
/// ——与 S4b「周次标签换行压住星期轴」同一类移动端事故，所以钉死不带文字。
class TasksBar extends StatelessWidget {
  const TasksBar({super.key});

  @override
  Widget build(BuildContext context) {
    final TaskPaneModel model = context.watch<TaskPaneModel>();
    return Column(
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(
              AppDimens.listPanePaddingH, AppDimens.s8, AppDimens.s8, 0),
          child: Row(children: <Widget>[Spacer(), _TopActions()]),
        ),
        _ChipsRow(model: model),
      ],
    );
  }
}

/// 标题行右端的三个图标按钮。
class _TopActions extends StatelessWidget {
  const _TopActions();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final SidebarModel sidebar = context.read<SidebarModel>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          key: const ValueKey<String>('btn-lists'),
          tooltip: '清单列表',
          visualDensity: VisualDensity.compact,
          onPressed: () => showListSheet(context),
          icon: Icon(Icons.view_list_outlined,
              size: 20, color: colors.textSecondary),
        ),
        IconButton(
          key: const ValueKey<String>('btn-new-list'),
          tooltip: '添加清单',
          visualDensity: VisualDensity.compact,
          onPressed: () => promptNewList(context, sidebar),
          icon: Icon(Icons.add_outlined, size: 20, color: colors.textSecondary),
        ),
        IconButton(
          key: const ValueKey<String>('btn-trash'),
          tooltip: '回收站',
          visualDensity: VisualDensity.compact,
          onPressed: () => sidebar.select(kTrash),
          icon: Icon(Icons.delete_outline,
              size: 20, color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// 时间视图 chips（今天 / 最近 7 天 / 所有 / 已完成）+ 行尾排序（F9）。
/// 横向可滚：411dp 下加长文案或大字号都不该把行撑爆（M4a S4b 的教训）。
class _ChipsRow extends StatelessWidget {
  const _ChipsRow({required this.model});

  final TaskPaneModel model;

  @override
  Widget build(BuildContext context) {
    final SidebarModel sidebar = context.watch<SidebarModel>();
    final List<_ChipSpec> specs = <_ChipSpec>[
      _ChipSpec('今天', kSmartToday, sidebar.todayCount),
      _ChipSpec('最近 7 天', kSmartNext7, sidebar.next7Count),
      _ChipSpec('所有', kSmartAll, sidebar.allCount),
      _ChipSpec('已完成', kSmartCompleted, sidebar.completedCount),
    ];
    // selectedId 只有一个槽（既装时间视图又装用户清单 id），「清单 × 时间视图」
    // 无法同时为真：停在用户清单上时四枚 chip 一律不亮。宁可什么都不亮，也不要亮
    // 一个会说谎的——假亮过的「所有」会出现三处矛盾：点这个已经亮着的 chip 会让
    // 内容从「仅该清单(含已完成)」暴变成「所有清单未完成」；它挂的又是全局未完成
    // 计数，与屏上内容对不上；清单面板里选中的还是那条清单行，同屏两个真相。
    // 要看「所有清单的待办」就点清单面板首行「全部清单」（那时 selectedId 是真值）。
    final bool listScoped = model.isUserList;
    return Row(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(AppDimens.listPanePaddingH,
                AppDimens.s8, AppDimens.s4, AppDimens.s4),
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
          ),
        ),
        // 智能视图强制按到期排序（§4），手动排序只对用户清单有意义。
        if (listScoped) _SortMenu(model: model),
        const SizedBox(width: AppDimens.s4),
      ],
    );
  }
}

class _ChipSpec {
  const _ChipSpec(this.label, this.id, this.count);

  final String label;
  final String id;
  final int count;
}

/// 排序（F9）：M6-A2 把入口从标题行挪到 chips 行末尾，四档与语义原样保留。
///
/// ⚠ 别再给 `PopupMenuButton` 传 `constraints` 想收按钮尺寸：那个参数是**弹层
/// 内容盒**的约束（`popup_menu.dart:1507` 文档 + :760 的 `ConstrainedBox`），
/// 写 `tightFor(width: 40, height: 40)` 会让整张菜单只有 40dp 宽，四条中文文案
/// 被折成「一字一行」（411dp 实测菜单占 114–434 高、宽 40，最后一项点不到）。
/// 按钮本身的尺寸要收就收 `style`/`padding`，默认 48dp 触区在本行里没有溢出风险
/// （chips 那侧是 `Expanded`，多宽都它先让）。
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.model});

  final TaskPaneModel model;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return PopupMenuButton<TaskSortMode>(
      key: const ValueKey<String>('btn-sort'),
      tooltip: '排序',
      padding: EdgeInsets.zero,
      iconSize: 20,
      color: colors.surface,
      icon: Icon(Icons.swap_vert, size: 20, color: colors.textSecondary),
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
