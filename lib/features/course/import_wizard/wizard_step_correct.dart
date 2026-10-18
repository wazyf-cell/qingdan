// 步 4：预览与人工校正（F30，§4.3 —— 本模块 UI 重心）。
//
// 三条原文规则在这里落地：状态三色 + 行内解释写清冲突对象；点行展开编辑器
// （移动 = 底部抽屉，同一个面板）；默认筛选就是「疑问 + 错误」，让「逐条检查」
// 变成「只看有问题的」（规则 5 的自动定位由此天然满足——列表里根本没有 ✓ 行）。
//
// 批量操作（规则 4）与移动端长按多选排在下一步增量，这里不含。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/week_rule.dart';
import 'package:qingdan/features/course/course_day_axis.dart';
import 'package:qingdan/features/course/course_edit_panel.dart';
import 'package:qingdan/features/course/course_setup.dart';
import 'package:qingdan/import/course/column_mapping.dart';
import 'package:qingdan/import/course/course_row_parser.dart';
import 'package:qingdan/theme/app_colors.dart';

import 'correction_batch_bar.dart';
import 'correction_parts.dart';
import 'correction_row_tile.dart';
import 'import_wizard_model.dart';
import 'import_wizard_types.dart';


class WizardStepCorrect extends StatefulWidget {
  const WizardStepCorrect({super.key, required this.isMobile});

  final bool isMobile;

  @override
  State<WizardStepCorrect> createState() => _WizardStepCorrectState();
}

class _WizardStepCorrectState extends State<WizardStepCorrect> {
  /// 默认只看有问题的（§4.3 规则 5）。
  final Set<RowStatus> _shown = <RowStatus>{RowStatus.warning, RowStatus.error};
  int? _expandedRow;

  ImportWizardModel get _model => context.read<ImportWizardModel>();

  List<CorrectionRow> get _visible => _model.listed
      .where((CorrectionRow r) => _shown.contains(r.parsed.status))
      .toList(growable: false);

  void _toggle(int rowNumber) {
    setState(() => _expandedRow = _expandedRow == rowNumber ? null : rowNumber);
  }

  Future<void> _editMobile(CorrectionRow r) async {
    final Course? base = r.parsed.course;
    final Course? edited = await showCourseEditor(context,
        course: base,
        isMobile: true,
        totalWeeks: _model.totalWeeks,
        maxSection: _model.maxSection);
    if (edited != null) _model.applyEdit(r.parsed.rowNumber, edited);
  }

  String? _notice;

  /// 处置后只给一条行内可撤销提示，不弹确认窗（§4.3 规则 4「不弹窗轰炸」）。
  void _undoable(String what, {int? count}) {
    setState(() => _notice = count == null ? what : '$what $count 行');
  }

  Future<void> _runBatch(BatchAction action) async {
    switch (action) {
      case BatchAction.ignore:
        _undoable('已忽略', count: _model.batchIgnore());
      case BatchAction.delete:
        _undoable('已删除', count: _model.batchDelete());
      case BatchAction.weeks:
        final List<int>? weeks = await pickWeeksDialog(context,
            totalWeeks: _model.totalWeeks,
            initial: const <int>[],
            title: '批量改周次（覆盖所选行的周次）');
        if (weeks != null) {
          _undoable('已改周次', count: _model.batchEdit(weeks: weeks));
        }
      case BatchAction.teacher:
      case BatchAction.location:
        final bool isTeacher = action == BatchAction.teacher;
        final String? text = await promptTextDialog(context,
            title: isTeacher ? '批量改老师' : '批量改地点');
        if (text == null) return;
        final int n = isTeacher
            ? _model.batchEdit(teacher: text)
            : _model.batchEdit(location: text);
        _undoable(isTeacher ? '已改老师' : '已改地点', count: n);
    }
  }

  void _quickAction(CorrectionRow r, RowQuickAction action) {
    switch (action) {
      case RowQuickAction.fillAllWeeks:
        final Course? c = r.parsed.course;
        if (c == null) return;
        _model.applyEdit(
            r.parsed.rowNumber,
            c.copyWith(
                weeks: <int>[for (int w = 1; w <= _model.totalWeeks; w++) w]));
      case RowQuickAction.ignore:
        _model.setDisposition(
            r.parsed.rowNumber,
            r.disposition == RowDisposition.ignored
                ? RowDisposition.keep
                : RowDisposition.ignored);
        if (r.disposition == RowDisposition.ignored) _undoable('已忽略');
      case RowQuickAction.remove:
        // 删除 = 移出预览（与「忽略」语义不同，§4.3 规则 6），可撤销。
        _model.setDisposition(r.parsed.rowNumber, RowDisposition.deleted);
        _undoable('已删除');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ImportWizardModel model = context.watch<ImportWizardModel>();
    final AppColors colors = AppColors.of(context);
    final List<CorrectionRow> visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CorrectionFilterBar(
            model: model,
            colors: colors,
            shown: _shown,
            onToggle: (RowStatus? only) => setState(() {
              _shown
                ..clear()
                ..addAll(only == null
                    ? RowStatus.values
                    : <RowStatus>{only});
            }),
            onProblem: () => setState(() {
              _shown
                ..clear()
                ..add(RowStatus.warning)
                ..add(RowStatus.error);
            })),
        if (model.selection.active)
          CorrectionBatchBar(
            model: model,
            colors: colors,
            onAction: _runBatch,
            onSelectAll: () => _model.selectAll(),
            onCancel: () => _model.clearSelection(),
          ),
        if (!widget.isMobile) CorrectionTableHeader(colors: colors),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(model.rows.isEmpty ? '没有可导入的行' : '当前筛选下没有行',
                      style: TextStyle(color: colors.textSecondary)),
                )
              : ListView.builder(
                  key: const ValueKey<String>('correction-list'),
                  itemCount: visible.length,
                  itemBuilder: (BuildContext context, int i) {
                    final CorrectionRow r = visible[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        CorrectionRowTile(
                          correction: r,
                          view: rowViewOf(r, model.mapping),
                          isMobile: widget.isMobile,
                          colors: colors,
                          expanded: _expandedRow == r.parsed.rowNumber,
                          selected: model.selection.numbers
                              .contains(r.parsed.rowNumber),
                          // 桌面常显勾选框（勾一个就进多选）；移动端按 §4.3 规则 8
                          // 靠长按进入，平时不占卡片宽度。
                          showCheck:
                              !widget.isMobile || model.selection.active,
                          onToggleSelect: () =>
                              _model.toggleSelected(r.parsed.rowNumber),
                          // 移动端「长按进入多选模式」（§4.3 规则 8）；多选态下
                          // 短按改成勾选，编辑走批量条之外的行点击。
                          onLongPress: () =>
                              _model.toggleSelected(r.parsed.rowNumber),
                          onTapRow: model.selection.active
                              ? () => _model.toggleSelected(r.parsed.rowNumber)
                              : (widget.isMobile
                                  ? () => _editMobile(r)
                                  : () => _toggle(r.parsed.rowNumber)),
                          onQuickAction: (RowQuickAction a) =>
                              _quickAction(r, a),
                        ),
                        if (_expandedRow == r.parsed.rowNumber &&
                            !widget.isMobile)
                          _InlineEditor(correction: r),
                      ],
                    );
                  },
                ),
        ),
        if (_notice != null && model.selection.canUndo)
          CorrectionUndoBar(
            text: _notice!,
            colors: colors,
            onUndo: () {
              _model.undoBatch();
              setState(() => _notice = null);
            },
          ),
        CorrectionGateBanner(model: model, colors: colors),
      ],
    );
  }
}

/// 行内展开的编辑器（桌面）。保存即写回这一行，不跳页（§4.3 规则 2）。
class _InlineEditor extends StatelessWidget {
  const _InlineEditor({required this.correction});

  final CorrectionRow correction;

  @override
  Widget build(BuildContext context) {
    final ImportWizardModel model = context.read<ImportWizardModel>();
    return Container(
      key: ValueKey<String>('edit-${correction.parsed.rowNumber}'),
      color: AppColors.of(context).surfaceHigh,
      child: CourseEditPanel(
        totalWeeks: model.totalWeeks,
        maxSection: model.maxSection,
        initial: correction.parsed.course,
        onSave: (Course c) =>
            model.applyEdit(correction.parsed.rowNumber, c),
      ),
    );
  }
}

/// 由解析行 + 映射拼出展示字段。✗ 行没有 Course 时退回原始单元格，
/// 让用户看见文件里写了什么（§6.3.1 不静默吞错）。
RowView rowViewOf(CorrectionRow r, ColumnMapping? mapping) {
  final ParsedCourseRow parsed = r.parsed;
  final Course? c = parsed.course;
  if (c != null) {
    return RowView(
      rowNumber: parsed.rowNumber,
      name: c.name,
      daySection:
          '${CourseDayAxis.nameOf(c.weekday)} 第${c.startSection}-${c.endSection}节',
      teacher: c.teacher ?? '',
      location: c.location ?? '',
      weeks: c.rawWeeksText ?? formatWeeks(c.weeks),
    );
  }
  String cell(CourseField f) {
    final int? i = mapping?.indexOf(f);
    if (i == null || i >= parsed.cells.length) return '';
    return parsed.cells[i].trim();
  }

  return RowView(
    rowNumber: parsed.rowNumber,
    name: cell(CourseField.name),
    daySection:
        '${cell(CourseField.weekday)} ${cell(CourseField.startSection)}-${cell(CourseField.endSection)}',
    teacher: cell(CourseField.teacher),
    location: cell(CourseField.location),
    weeks: cell(CourseField.weeks),
  );
}
