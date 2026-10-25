import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 作息编辑面板底部的错误行 + 添加/保存按钮。
///
/// 从 `timetable_editor.dart` 拆出（加入整页保存/返回拦截后触 300 行红线）。
class TimetableEditorFooter extends StatelessWidget {
  const TimetableEditorFooter({
    super.key,
    required this.error,
    required this.canAdd,
    required this.canSave,
    required this.showSaveButton,
    required this.onAdd,
    required this.onSave,
  });

  final String? error;
  final bool canAdd;
  final bool canSave;
  final bool showSaveButton;
  final VoidCallback onAdd;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.s4),
            child: Text(
              error!,
              key: const ValueKey<String>('tt-error'),
              style: TextStyle(fontSize: 12, color: colors.overdue),
            ),
          ),
        Row(
          children: <Widget>[
            TextButton(
              key: const ValueKey<String>('tt-add'),
              onPressed: canAdd ? onAdd : null,
              child: const Text('＋ 添加一节'),
            ),
            const Spacer(),
            if (showSaveButton)
              FilledButton(
                key: const ValueKey<String>('tt-save'),
                onPressed: canSave ? onSave : null,
                child: const Text('保存'),
              ),
          ],
        ),
      ],
    );
  }
}
