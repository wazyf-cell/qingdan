// 批量操作条与两个批量弹层（§4.3 规则 4）。
//
// 勾选后出现「已选 N · 全选 · 批量▾ · 取消」；批量删除/忽略**不弹确认窗**，
// 直接生效并在底部给一条可撤销的 toast（原文：「一次 toast 级确认即可，
// 不弹窗轰炸」）。

import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'import_wizard_model.dart';
import '../week_chip_picker.dart';

enum BatchAction { ignore, delete, weeks, teacher, location }

const Map<BatchAction, String> batchActionLabel = <BatchAction, String>{
  BatchAction.ignore: '批量忽略',
  BatchAction.delete: '批量删除',
  BatchAction.weeks: '批量改周次',
  BatchAction.teacher: '批量改老师',
  BatchAction.location: '批量改地点',
};

class CorrectionBatchBar extends StatelessWidget {
  const CorrectionBatchBar({
    super.key,
    required this.model,
    required this.colors,
    required this.onAction,
    required this.onSelectAll,
    required this.onCancel,
  });

  final ImportWizardModel model;
  final AppColors colors;
  final void Function(BatchAction action) onAction;
  final VoidCallback onSelectAll;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final int n = model.selection.numbers.length;
    return Container(
      key: const ValueKey<String>('batch-bar'),
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.s12, vertical: AppDimens.s4),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: <Widget>[
          Text('已选 $n', style: const TextStyle(fontSize: 13)),
          const SizedBox(width: AppDimens.s12),
          TextButton(
            key: const ValueKey<String>('batch-select-all'),
            onPressed: onSelectAll,
            child: const Text('全选'),
          ),
          PopupMenuButton<BatchAction>(
            key: const ValueKey<String>('batch-menu'),
            tooltip: '批量',
            onSelected: onAction,
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<BatchAction>>[
              for (final BatchAction a in BatchAction.values)
                PopupMenuItem<BatchAction>(
                    value: a, child: Text(batchActionLabel[a]!)),
            ],
            child: Text('批量▾',
                style: TextStyle(color: colors.accent, fontSize: 13)),
          ),
          const Spacer(),
          TextButton(
            key: const ValueKey<String>('batch-cancel'),
            onPressed: onCancel,
            child: Text('取消', style: TextStyle(color: colors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// 批量改周次：复用课表编辑器里那套 chip 选择器（同一份实现，别写第二套）。
Future<List<int>?> pickWeeksDialog(
  BuildContext context, {
  required int totalWeeks,
  required List<int> initial,
  required String title,
}) async {
  List<int> picked = <int>[...initial];
  await showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        // 直接复用课表编辑器里的 WeekChipPicker（同一份 chip 网格 + 全选/单双周），
        // 选中的周次用 StatefulBuilder 暂存在这里。
        child: StatefulBuilder(builder: (BuildContext ctx2, StateSetter setInner) {
          return WeekChipPicker(
            totalWeeks: totalWeeks,
            selected: picked,
            onChanged: (List<int> v) => setInner(() => picked = v),
          );
        }),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消')),
        FilledButton(
            key: const ValueKey<String>('weeks-ok'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定')),
      ],
    ),
  );
  return picked.isEmpty ? null : picked;
}

/// 批量改老师 / 地点：一个输入框，留空表示清空（界面上给「留空即清空」提示）。
Future<String?> promptTextDialog(BuildContext context,
        {required String title, String initial = ''}) =>
    showDialog<String>(
      context: context,
      builder: (BuildContext ctx) =>
          _BatchTextDialog(title: title, initial: initial),
    );

/// 整个对话框（含标题/输入框/两个按钮）由一个 State 持有控制器。
///
/// 控制器不能在 `await showDialog` 之后立刻 dispose：那时退场动画还没走完，
/// TextField 还挂在树上——真机 411dp 上开着键盘点「取消」或「确定」都直接
/// 红屏 `_dependents.isEmpty`（widget 测试里不复现，因为假时钟没有 IME）。
class _BatchTextDialog extends StatefulWidget {
  const _BatchTextDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_BatchTextDialog> createState() => _BatchTextDialogState();
}

class _BatchTextDialogState extends State<_BatchTextDialog> {
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
      content: SizedBox(
        width: 360,
        child: TextField(
          key: const ValueKey<String>('batch-text-field'),
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: '内容（留空即清空）'),
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(
            key: const ValueKey<String>('text-ok'),
            onPressed: _submit,
            child: const Text('确定')),
      ],
    );
  }
}
