import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';

/// 列表区键盘快捷键（§3.4）：
/// Ctrl+N 聚焦添加、Ctrl+1..4 切智能清单、Space 完成、Delete 删除、
/// ↑↓ 移动选中、Enter 开详情、Esc 关详情、Ctrl+D 日历未实现提示。
class ListShortcuts extends StatelessWidget {
  const ListShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            const _FocusAddIntent(),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true):
            const _SelectSmartIntent(kSmartToday),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true):
            const _SelectSmartIntent(kSmartNext7),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true):
            const _SelectSmartIntent(kSmartAll),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true):
            const _SelectSmartIntent(kSmartCompleted),
        const SingleActivator(LogicalKeyboardKey.space): const _ToggleIntent(),
        const SingleActivator(LogicalKeyboardKey.delete): const _DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const _MoveIntent(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const _MoveIntent(-1),
        const SingleActivator(LogicalKeyboardKey.enter):
            const _OpenDetailIntent(),
        const SingleActivator(LogicalKeyboardKey.escape):
            const _CloseDetailIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true):
            const _CalendarIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _FocusAddIntent: _GuardedAction<_FocusAddIntent>(
            onInvoke: (_) => _model(context).focusQuickAdd(),
          ),
          _SelectSmartIntent: _GuardedAction<_SelectSmartIntent>(
            onInvoke: (intent) =>
                context.read<SidebarModel>().select(intent.viewId),
          ),
          _ToggleIntent: _GuardedAction<_ToggleIntent>(
            onInvoke: (_) {
              final TaskPaneModel model = _model(context);
              final String? id = model.selectedTaskId;
              final Task? task = _byId(model, id);
              if (task != null) model.toggleComplete(task);
              return null;
            },
          ),
          _DeleteIntent: _GuardedAction<_DeleteIntent>(
            onInvoke: (_) {
              final TaskPaneModel model = _model(context);
              final Task? task = _byId(model, model.selectedTaskId);
              if (task != null) _deleteWithUndo(context, model, task);
              return null;
            },
          ),
          _MoveIntent: _GuardedAction<_MoveIntent>(
            onInvoke: (intent) => _model(context).moveSelection(intent.delta),
          ),
          _OpenDetailIntent: _GuardedAction<_OpenDetailIntent>(
            onInvoke: (_) => _model(context).openDetail(),
          ),
          _CloseDetailIntent: _GuardedAction<_CloseDetailIntent>(
            onInvoke: (_) => _model(context).closeDetail(),
          ),
          _CalendarIntent: _GuardedAction<_CalendarIntent>(
            onInvoke: (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日历视图尚未实现（P1）')),
              );
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }

  static TaskPaneModel _model(BuildContext context) =>
      context.read<TaskPaneModel>();

  static Task? _byId(TaskPaneModel model, String? id) {
    if (id == null) return null;
    for (final Task t in model.tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  static void _deleteWithUndo(
      BuildContext context, TaskPaneModel model, Task task) {
    model.deleteTask(task).then((String title) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除「$title」'),
          // 带 action 的 SnackBar 缺省 `persist: true`（Flutter 3.47.5
          // snack_bar.dart:303），会无视 duration 常驻；撤销入口在回收站里也有一份。
          duration: const Duration(seconds: 5),
          persist: false,
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => model.undoDelete(task.id),
          ),
        ),
      );
    });
  }
}

class _FocusAddIntent extends Intent {
  const _FocusAddIntent();
}

class _SelectSmartIntent extends Intent {
  const _SelectSmartIntent(this.viewId);
  final String viewId;
}

class _ToggleIntent extends Intent {
  const _ToggleIntent();
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);
  final int delta;
}

class _OpenDetailIntent extends Intent {
  const _OpenDetailIntent();
}

class _CloseDetailIntent extends Intent {
  const _CloseDetailIntent();
}

class _CalendarIntent extends Intent {
  const _CalendarIntent();
}

/// 带文本框守卫的 Action：焦点在任意 EditableText 内时 isActionEnabled
/// 返回 false，按键不被 Shortcuts 消费、继续下传给文本框（否则快速添加
/// 的回车/空格等会被这里的快捷键吃掉）。
class _GuardedAction<T extends Intent> extends CallbackAction<T> {
  _GuardedAction({required super.onInvoke});

  /// TextField 聚焦时 primaryFocus 的 context.widget 是 Focus（Focus 挂在
  /// EditableText 内层），所以要沿祖先链找 EditableTextState 才判得准。
  static bool _editingText() {
    final BuildContext? c = FocusManager.instance.primaryFocus?.context;
    if (c == null) return false;
    if (c.widget is EditableText) return true;
    return c.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  bool get isActionEnabled => !_editingText();
}
