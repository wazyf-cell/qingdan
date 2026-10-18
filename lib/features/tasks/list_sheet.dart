import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/task_list_use_case.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_actions.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_view.dart'
    show kInboxName;
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 半屏「清单」面板（M5 定案第 4 条）。
///
/// 抽屉在窄屏下线后，这里就是切换 / 新建 / 重命名 / 删除清单的唯一入口。
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
                  onPressed: () => showCreateListDialog(context, model),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppDimens.s8),
              children: <Widget>[
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
    return PopupMenuButton<String>(
      key: ValueKey<String>('listMenu:${list.id}'),
      tooltip: '清单操作',
      iconSize: 20,
      padding: EdgeInsets.zero,
      color: colors.surface,
      icon: Icon(Icons.more_vert, size: 18, color: colors.textSecondary),
      onSelected: (String v) => v == 'rename'
          ? _rename(context, list)
          : _delete(context, list),
      itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
        PopupMenuItem<String>(
            value: 'delete',
            enabled: !isInbox,
            child: Text('删除', style: TextStyle(color: isInbox ? colors.textFaint : colors.overdue))),
      ],
    );
  }

  Future<void> _rename(BuildContext context, TaskList list) async {
    final SidebarModel sidebar = context.read<SidebarModel>();
    final TaskListUseCase useCase = context.read<TaskListUseCase>();
    final String? name = await _askText(
        context, title: '重命名清单', initial: list.name, confirmLabel: '保存');
    if (name == null || name.isEmpty || name == list.name) return;
    await useCase.rename(list, name);
    await sidebar.load();
  }

  Future<void> _delete(BuildContext context, TaskList list) async {
    final SidebarModel sidebar = context.read<SidebarModel>();
    final TaskListUseCase useCase = context.read<TaskListUseCase>();
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text('删除「${list.name}」？'),
            content: const Text('清单里的任务不会丢，会移到收集箱。'),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('删除')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await useCase.delete(list.id);
    // 先改视图再重载：删掉正在看的清单后若仍指向它，列表会显示已删清单的空任务，
    // 侧栏重载也读不到那一行。
    if (sidebar.selectedId == list.id) sidebar.select(kSmartToday);
    await sidebar.load();
  }
}

Future<String?> _askText(BuildContext context,
    {required String title,
    required String initial,
    required String confirmLabel}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext _) => _TextDialog(
        title: title, initial: initial, confirmLabel: confirmLabel),
  );
}

/// 通用文本输入对话框。
///
/// 控制器由对话框自己持有、在 `dispose()` 里释放：S5-f 的 Android 真机教训是
/// 在 `await showDialog` 之后再 dispose，会撞上退场动画里还挂着的 TextField，
/// 开着键盘点「确定/取消/遮罩」必红屏 `_dependents.isEmpty`。
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final String confirmLabel;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '清单名称'),
        onSubmitted: (String _) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        TextButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
