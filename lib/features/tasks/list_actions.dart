import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/task_list_use_case.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_actions.dart'
    show showCreateListDialog;
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';

/// 新建清单（M6-A2）：顶栏「＋」与半屏面板的添加按钮都走这里。
///
/// 「新建」不另写一份弹窗：转发到 `sidebar_actions.dart` 的 [showCreateListDialog]
/// （桌面侧栏也在用它），三处入口一份代码，避免以后改一处漏两处。
/// 本文件的「重命名 / 删除」从 `list_sheet.dart` 搬来，为的是面板本体留在 300 行
/// 以内，且输入框对话框只有一个实现。写库一律经 [TaskListUseCase]，UI 不碰 DAO。
Future<void> promptNewList(BuildContext context, SidebarModel sidebar) =>
    showCreateListDialog(context, sidebar);

/// 重命名清单：改名 → 写库 → 重载侧栏（同一条清单内改名，视图不必动）。
Future<void> renameList(
  BuildContext context, {
  required SidebarModel sidebar,
  required TaskList list,
}) async {
  final TaskListUseCase useCase = context.read<TaskListUseCase>();
  final String? name = await askText(context,
      title: '重命名清单',
      initial: list.name,
      hint: '清单名称',
      confirmLabel: '保存');
  if (name == null || name.isEmpty || name == list.name) return;
  await useCase.rename(list, name);
  await sidebar.load();
}

/// 删除清单：确认后任务落回收集箱（迁移 v2 语义），并先把视图切走。
Future<void> deleteList(
  BuildContext context, {
  required SidebarModel sidebar,
  required TaskList list,
}) async {
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

/// 单行文本输入对话框，返回去掉首尾空白的输入；取消返回 null。
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String initial,
  required String hint,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext _) => _TextDialog(
      title: title,
      initial: initial,
      hint: hint,
      confirmLabel: confirmLabel,
    ),
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
    required this.hint,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final String hint;
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
        decoration: InputDecoration(hintText: widget.hint),
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
