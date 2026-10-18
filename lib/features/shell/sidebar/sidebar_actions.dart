import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/task_list_use_case.dart';

import 'sidebar_model.dart';

/// 「新建清单」弹窗：输入名称 → TaskListUseCase.create → 刷新侧栏。
///
/// 弹窗是 StatefulWidget 且自持控制器：在 `await showDialog` 之后 dispose 会
/// 撞上退场动画里还挂着的 TextField，开着键盘点按钮必红屏 `_dependents.isEmpty`
/// （M4a S5-f 的 Android 真机教训，同一个坑不再踩第二遍）。
Future<void> showCreateListDialog(
    BuildContext context, SidebarModel model) async {
  final TaskListUseCase useCase = context.read<TaskListUseCase>();
  final String? name = await showDialog<String>(
    context: context,
    builder: (BuildContext _) => const _CreateListDialog(),
  );
  if (name == null || name.isEmpty) return;
  await useCase.create(name: name, sortOrder: model.lists.length);
  await model.load();
}

class _CreateListDialog extends StatefulWidget {
  const _CreateListDialog();

  @override
  State<_CreateListDialog> createState() => _CreateListDialogState();
}

class _CreateListDialogState extends State<_CreateListDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建清单'),
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
        TextButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}
