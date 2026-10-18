import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'due_format.dart';

/// 任务行右键菜单（§3.3）：打开详情 / 编辑日期 / 切换优先级▸四级子菜单 /
/// 复制为文本 / 移动到清单▸ / 删除 / 彻底删除（仅回收站）。
/// 菜单项高 32dp。
Future<void> showTaskRowMenu(
  BuildContext context,
  Offset position, {
  required Task task,
  required bool restoreMode,
  required List<TaskList> lists,
  required VoidCallback onOpenDetail,
  required VoidCallback onDelete,
  required VoidCallback onRestore,
  required VoidCallback onDeleteForever,
  required ValueChanged<TaskPriority> onChangePriority,
  required VoidCallback onEditDate,
  required VoidCallback onCopyAsText,
  required ValueChanged<String> onMoveToList,
}) async {
  final AppColors colors = AppColors.of(context);
  await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx + 1, position.dy + 1),
    color: colors.surface,
    elevation: 8,
    shadowColor: const Color(0x33000000),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
    ),
    items: <PopupMenuEntry<String>>[
      _item('detail', '打开详情'),
      if (!restoreMode) _item('date', '编辑日期'),
      if (!restoreMode)
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _PrioritySubMenu(
            label: '切换优先级',
            colors: colors,
            entries: <String, TaskPriority>{
              '高': TaskPriority.high,
              '中': TaskPriority.medium,
              '低': TaskPriority.low,
              '无': TaskPriority.none,
            },
            onSelected: onChangePriority,
          ),
        ),
      _item('copy', '复制为文本'),
      if (!restoreMode && lists.isNotEmpty)
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _MoveSubMenu(
            label: '移动到清单',
            colors: colors,
            lists: lists,
            onSelected: onMoveToList,
          ),
        ),
      if (!restoreMode) _item('delete', '删除'),
      if (restoreMode) _item('restore', '恢复'),
      if (restoreMode) _item('forever', '彻底删除'),
    ],
  ).then((String? value) {
    if (value == null) return;
    switch (value) {
      case 'detail':
        onOpenDetail();
      case 'date':
        onEditDate();
      case 'copy':
        onCopyAsText();
      case 'delete':
        onDelete();
      case 'restore':
        onRestore();
      case 'forever':
        onDeleteForever();
    }
  });
}

PopupMenuEntry<String> _item(String value, String label) =>
    PopupMenuItem<String>(
      value: value,
      height: 32,
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );

/// 悬停展开子菜单的通用行：hover 在右侧弹出浮层子菜单（§3.3）。
class _HoverSubMenu extends StatefulWidget {
  const _HoverSubMenu({
    required this.label,
    required this.colors,
    required this.itemBuilder,
  });

  final String label;
  final AppColors colors;
  final List<Widget> Function(BuildContext menuContext) itemBuilder;

  @override
  State<_HoverSubMenu> createState() => _HoverSubMenuState();
}

class _HoverSubMenuState extends State<_HoverSubMenu> {
  OverlayEntry? _entry;
  double _top = 0;
  double _left = 0;

  void _open() {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset pos = box.localToGlobal(Offset.zero);
    _top = pos.dy - 8;
    _left = pos.dx + box.size.width - 8;
    _entry = OverlayEntry(
      builder: (BuildContext ctx) => Stack(
        children: <Widget>[
          Positioned(
            left: _left,
            top: _top,
            child: Material(
              color: widget.colors.surface,
              elevation: 8,
              shadowColor: const Color(0x33000000),
              borderRadius:
                  BorderRadius.circular(AppDimens.radiusDesktop),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.itemBuilder(ctx),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (PointerEnterEvent _) => _open(),
      onExit: (PointerExitEvent _) => _close(),
      child: SizedBox(
        height: 32,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppDimens.s16),
          child: Row(
            children: <Widget>[
              Text(widget.label, style: const TextStyle(fontSize: 13)),
              const Spacer(),
              Icon(Icons.chevron_right,
                  size: 16, color: widget.colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「切换优先级」子菜单：四级旗标色行。
class _PrioritySubMenu extends StatelessWidget {
  const _PrioritySubMenu({
    required this.label,
    required this.colors,
    required this.entries,
    required this.onSelected,
  });

  final String label;
  final AppColors colors;
  final Map<String, TaskPriority> entries;
  final ValueChanged<TaskPriority> onSelected;

  @override
  Widget build(BuildContext context) {
    return _HoverSubMenu(
      label: label,
      colors: colors,
      itemBuilder: (BuildContext menuContext) => <Widget>[
        for (final MapEntry<String, TaskPriority> e in entries.entries)
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              onSelected(e.value);
            },
            child: SizedBox(
              height: 32,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.s16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 3,
                      height: 14,
                      color: priorityColor(e.value, colors),
                    ),
                    const SizedBox(width: AppDimens.s8),
                    Text(e.key, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 「移动到清单」子菜单：全部用户清单（§3.3）。
class _MoveSubMenu extends StatelessWidget {
  const _MoveSubMenu({
    required this.label,
    required this.colors,
    required this.lists,
    required this.onSelected,
  });

  final String label;
  final AppColors colors;
  final List<TaskList> lists;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _HoverSubMenu(
      label: label,
      colors: colors,
      itemBuilder: (BuildContext menuContext) => <Widget>[
        for (final TaskList list in lists)
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              onSelected(list.id);
            },
            child: SizedBox(
              height: 32,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.s16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(list.name,
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
