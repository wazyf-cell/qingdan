import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_view.dart'
    show kInboxName;
import 'package:qingdan/features/tasks/list_actions.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 半屏「清单」面板（M5 定案第 4 条，M6-A2 补「全部清单」首行）。
///
/// 抽屉在窄屏下线后，这里就是切换 / 重命名 / 删除清单的入口（新建与顶栏「＋」
/// 共用 `list_actions.dart` 的同一条实现）。列表首行固定「全部清单」= 智能视图
/// 「所有」：没有它，用户在手机上一旦进了某个清单就只能靠 chips 绕回去。
/// 高度按定案取屏高 50%：`showModalBottomSheet` 默认只包内容且上限半屏，
/// 清单多于 6 条时会被裁掉，所以显式 `isScrollControlled` + `maxHeight`。
Future<void> showListSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppDimens.radiusMobile)),
    ),
    constraints:
        BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
    builder: (BuildContext _) => const ListSheet(),
  );
}

class ListSheet extends StatelessWidget {
  const ListSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final SidebarModel model = context.watch<SidebarModel>();
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: AppDimens.s8),
              decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppDimens.s16, 0, AppDimens.s4, AppDimens.s4),
            child: Row(
              children: <Widget>[
                Expanded(
                    child: Text('我的清单',
                        style: AppTypography.panelTitle
                            .copyWith(color: colors.textPrimary))),
                IconButton(
                  tooltip: '新建清单',
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => promptNewList(context, model),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppDimens.s8),
              children: <Widget>[
                _AllListsRow(
                  count: model.allCount,
                  selected: model.selectedId == kSmartAll,
                  onTap: () {
                    model.select(kSmartAll);
                    Navigator.of(context).pop();
                  },
                ),
                for (final TaskList list in model.lists)
                  _SheetListRow(
                    list: list,
                    count: model.countFor(list.id),
                    selected: model.selectedId == list.id,
                    onTap: () {
                      model.select(list.id);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 固定首行「全部清单」（M6-A2）：等价于智能视图「所有」= 所有清单的未完成待办。
/// 两行文案（名称 + 副文案），所以行高比单行的用户清单行高一档，同时保住 44dp
/// 触控下限。
class _AllListsRow extends StatelessWidget {
  const _AllListsRow({
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color label = selected ? colors.accent : colors.textPrimary;
    return InkWell(
      key: const ValueKey<String>('list-all'),
      onTap: onTap,
      child: Container(
        color: selected ? colors.accentFaint : null,
        height: AppDimens.sidebarItemHeight + AppDimens.s16,
        padding: const EdgeInsets.only(left: AppDimens.s16),
        child: Row(
          children: <Widget>[
            Icon(Icons.all_inclusive,
                size: 18,
                color: selected ? colors.accent : colors.textSecondary),
            const SizedBox(width: AppDimens.s8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('全部清单',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(color: label)),
                  Text('所有清单的待办',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.meta
                          .copyWith(color: colors.textSecondary)),
                ],
              ),
            ),
            if (selected) ...<Widget>[
              Icon(Icons.check, size: 16, color: colors.accent),
              const SizedBox(width: AppDimens.s4),
            ],
            Text('$count',
                style: AppTypography.counter
                    .copyWith(color: colors.textSecondary)),
            // 末尾留出用户清单行那个 ⋮ 的宽度，两行的计数才能右对齐。
            const SizedBox(width: AppDimens.s32),
          ],
        ),
      ),
    );
  }
}

class _SheetListRow extends StatelessWidget {
  const _SheetListRow({
    required this.list,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final TaskList list;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  bool get _isInbox => list.name == kInboxName;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? colors.accentFaint : null,
        height: AppDimens.sidebarItemHeight + AppDimens.s8,
        padding: const EdgeInsets.only(left: AppDimens.s16),
        child: Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: colors.divider),
            ),
            const SizedBox(width: AppDimens.s8),
            Expanded(
              child: Text(
                _isInbox ? '$kInboxName（内置）' : list.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                    color:
                        selected ? colors.accent : colors.textPrimary),
              ),
            ),
            Text('$count',
                style: AppTypography.counter
                    .copyWith(color: colors.textSecondary)),
            _RowMenu(list: list, isInbox: _isInbox),
          ],
        ),
      ),
    );
  }
}

/// 行尾 ⋮：重命名 / 删除。内置「收集箱」不可删（迁移 v2 seed 行）。
class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.list, required this.isInbox});

  final TaskList list;
  final bool isInbox;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final SidebarModel sidebar = context.read<SidebarModel>();
    return PopupMenuButton<String>(
      key: ValueKey<String>('listMenu:${list.id}'),
      tooltip: '清单操作',
      iconSize: 20,
      padding: EdgeInsets.zero,
      color: colors.surface,
      icon: Icon(Icons.more_vert, size: 18, color: colors.textSecondary),
      onSelected: (String v) => v == 'rename'
          ? renameList(context, sidebar: sidebar, list: list)
          : deleteList(context, sidebar: sidebar, list: list),
      itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
        PopupMenuItem<String>(
            value: 'delete',
            enabled: !isInbox,
            child: Text('删除', style: TextStyle(color: isInbox ? colors.textFaint : colors.overdue))),
      ],
    );
  }
}
