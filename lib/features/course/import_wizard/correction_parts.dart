// 校正界面的三块零件：筛选条、桌面表头、闸门横幅。
//
// 与 `wizard_step_correct.dart` 分文件是因为合起来过了 300 行硬红线。

import 'package:flutter/material.dart';

import 'package:qingdan/import/course/course_row_parser.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'correction_row_tile.dart';
import 'import_wizard_model.dart';


class CorrectionFilterBar extends StatelessWidget {
  const CorrectionFilterBar({
    super.key,
    required this.model,
    required this.colors,
    required this.shown,
    required this.onToggle,
    required this.onProblem,
  });

  final ImportWizardModel model;
  final AppColors colors;
  final Set<RowStatus> shown;
  final void Function(RowStatus? only) onToggle;
  final VoidCallback onProblem;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.s12, vertical: AppDimens.s8),
      child: Wrap(
        spacing: AppDimens.s8,
        children: <Widget>[
          FilterChip(
            key: const ValueKey<String>('filter-all'),
            label: Text('全部 ${model.listedCount}'),
            selected: shown.length == RowStatus.values.length,
            onSelected: (_) => onToggle(null),
          ),
          FilterChip(
            key: const ValueKey<String>('filter-problem'),
            label: Text('需处理 ${model.countOf(RowStatus.error) + model.countOf(RowStatus.warning)}'),
            selected: shown.contains(RowStatus.error) &&
                shown.contains(RowStatus.warning) &&
                !shown.contains(RowStatus.ok),
            onSelected: (_) => onProblem(),
          ),
          FilterChip(
            key: const ValueKey<String>('filter-ok'),
            label: Text('✓ 正常 ${model.countOf(RowStatus.ok)}'),
            selected: shown.length == 1 && shown.contains(RowStatus.ok),
            onSelected: (_) => onToggle(RowStatus.ok),
          ),
          FilterChip(
            key: const ValueKey<String>('filter-error'),
            label: Text('✗ 错误 ${model.countOf(RowStatus.error)}'),
            selected: shown.length == 1 && shown.contains(RowStatus.error),
            onSelected: (_) => onToggle(RowStatus.error),
          ),
        ],
      ),
    );
  }
}

class CorrectionTableHeader extends StatelessWidget {
  const CorrectionTableHeader({super.key, required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final TextStyle style =
        TextStyle(fontSize: 12, color: colors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.s12, vertical: AppDimens.s4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
        color: colors.surface,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
              width: CorrectionRowTile.leftWidth,
              child: Text('状态 / 课程', style: style)),
          SizedBox(width: 96, child: Text('星期节次', style: style)),
          SizedBox(width: 96, child: Text('老师', style: style)),
          SizedBox(width: 130, child: Text('地点', style: style)),
          Expanded(child: Text('周次', style: style)),
        ],
      ),
    );
  }
}

class CorrectionGateBanner extends StatelessWidget {
  const CorrectionGateBanner(
      {super.key, required this.model, required this.colors});

  final ImportWizardModel model;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final int blocking = model.blockingRows.length;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.s12, vertical: AppDimens.s8),
      decoration: BoxDecoration(
        color: blocking == 0 ? colors.surface : colors.surfaceHigh,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Text(
        blocking == 0
            ? '共 ${model.listedCount} 行，可以进入下一步'
            : '还有 $blocking 条错误未处理：修正或忽略后才能继续',
        key: const ValueKey<String>('gate-banner'),
        style: TextStyle(
            fontSize: 12, color: blocking == 0 ? colors.textSecondary : colors.overdue),
      ),
    );
  }
}

/// 「已忽略 2 行 · 撤销」条。
///
/// 原本用 SnackBar，实测桌面端 SnackBar 画在 Dialog 路由底下、点不到撤销；
/// 放进校正步内部两端同形，也仍然满足「一次 toast 级提示、不弹窗轰炸」。
class CorrectionUndoBar extends StatelessWidget {
  const CorrectionUndoBar(
      {super.key, required this.text, required this.colors, required this.onUndo});

  final String text;
  final AppColors colors;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('undo-bar'),
      color: colors.surfaceHigh,
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.s12, vertical: AppDimens.s4),
      child: Row(
        children: <Widget>[
          Expanded(
              child: Text(text,
                  key: const ValueKey<String>('undo-text'),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary))),
          TextButton(
            key: const ValueKey<String>('undo-batch'),
            onPressed: onUndo,
            child: const Text('撤销'),
          ),
        ],
      ),
    );
  }
}
