// 导入向导模型 · 步 3（进入预览前的装配）与步 4（校正/多选）的状态
// （§十二.2 从 `import_wizard_model.dart` 按职责搬出：搬家不改行为，
// 方法体与文案与原文件逐字一致）。

import 'package:flutter/foundation.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/import/course/column_mapping.dart';
import 'package:qingdan/import/course/course_row_parser.dart';
import 'package:qingdan/import/course/schedule_file.dart';

import 'import_wizard_batch.dart';
import 'import_wizard_types.dart';

/// 步 3 / 步 4：行解析、处置与多选批量操作。
///
/// 跨职责成员（学期、作息、当前步、映射、表、多选状态）声明为抽象，
/// 由应用了本 mixin 的具体类（`ImportWizardModel`）满足——签名与原实现一致。
mixin WizardCorrectSteps on ChangeNotifier {
  Semester? get semester;
  List<TimeDetail> get details;
  WizardStep get step;
  set step(WizardStep value);
  ColumnMapping? get mapping;
  ScheduleTable? get table;
  RowSelection get selection;

  // ---- 步 4 ----
  final List<CorrectionRow> rows = <CorrectionRow>[];

  int get totalWeeks => semester?.totalWeeks ?? 0;

  /// 预览列表的条数（删除的行不计，§4.3 规则 6）。
  int get listedCount => listed.length;

  int _countDisposition(RowDisposition d) =>
      rows.where((CorrectionRow r) => r.disposition == d).length;

  /// 忽略（仍显示在列表里，可撤销）与删除（移出预览）的条数。
  int get ignoredCount => _countDisposition(RowDisposition.ignored);
  int get deletedCount => _countDisposition(RowDisposition.deleted);
  int get maxSection => details.isEmpty
      ? 0
      : details.map((TimeDetail d) => d.section).reduce((int a, int b) => a > b ? a : b);

  List<CorrectionRow> get blockingRows =>
      rows.where((CorrectionRow r) => r.blocksImport).toList(growable: false);

  int countOf(RowStatus status) => rows
      .where((CorrectionRow r) => r.parsed.status == status && r.kept)
      .length;

  /// 将要落库的行（已过滤忽略与删除）。
  List<Course> get importableCourses => <Course>[
        for (final CorrectionRow r in rows)
          if (r.kept && r.parsed.course != null) r.parsed.course!,
      ];

  /// 这批课里最大的周次。`weeks` 已升序归一化，末元素即最大周。
  ///
  /// 导入完拿它去抬**选中那个学期**的总周数（2026-10-18 定案，M6-D §7.5
  /// 起不再假设「active 学期」）：周数是**翻页上限**，不抬的话排在学期外面的
  /// 课查得到却翻不到，用户看到的就是「只到 16 周」。
  int get maxImportedWeek {
    int top = 0;
    for (final Course c in importableCourses) {
      if (c.weeks.isNotEmpty && c.weeks.last > top) top = c.weeks.last;
    }
    return top;
  }

  /// 进入步 4：按当前映射与学期作息解析。**每次进入都重算**，所以从步 5 回跳
  /// 到步 2 改过映射后，旧校正在这里自然作废（§3.1:168）。
  void buildRows() {
    final ScheduleTable? t = table;
    final ColumnMapping? m = mapping;
    final Semester? s = semester;
    rows.clear();
    if (t != null && m != null && s != null) {
      final ParseSummary summary =
          parseCourseRows(t, m, semesterId: s.id, totalWeeks: s.totalWeeks);
      rows.addAll(<CorrectionRow>[
        for (final ParsedCourseRow r in summary.rows) CorrectionRow(r),
      ]);
    }
    step = WizardStep.correct;
    notifyListeners();
  }

  // ================= 步 4：校正 =================

  /// 列表里可见的行（删除 = 移出预览，§4.3 规则 6）。
  List<CorrectionRow> get listed => rows
      .where((CorrectionRow r) => r.disposition != RowDisposition.deleted)
      .toList(growable: false);

  /// 下面几个是界面用的薄委托：调完统一 notifyListeners。
  int batchIgnore() {
    final int n = selection.applyDisposition(RowDisposition.ignored);
    notifyListeners();
    return n;
  }

  int batchDelete() {
    final int n = selection.applyDisposition(RowDisposition.deleted);
    notifyListeners();
    return n;
  }

  int batchEdit({List<int>? weeks, String? teacher, String? location}) {
    final int n =
        selection.edit(weeks: weeks, teacher: teacher, location: location);
    notifyListeners();
    return n;
  }

  void toggleSelected(int rowNumber) {
    selection.toggle(rowNumber);
    notifyListeners();
  }

  void selectAll() {
    selection.selectAllListed();
    notifyListeners();
  }

  void clearSelection() {
    selection.clear();
    notifyListeners();
  }

  void undoBatch() {
    selection.undoLast();
    notifyListeners();
  }

  /// 单行处置（「修正▾」与卡片上的忽略/删除），顺带记快照供撤销。
  void setDisposition(int rowNumber, RowDisposition d) {
    final CorrectionRow? r = rowAt(rowNumber);
    if (r == null) return;
    selection.rememberSingle(rowNumber, r.disposition);
    r.disposition = d;
    notifyListeners();
  }

  /// 编辑面板改完一行：就地替换 course 并把 ✗ 降级为 ✓（§4.3 规则 2 实时重校验）。
  void applyEdit(int rowNumber, Course edited) {
    final CorrectionRow? r = rowAt(rowNumber);
    if (r == null) return;
    r.parsed
      ..course = edited
      ..status = RowStatus.ok
      ..messages.clear();
    notifyListeners();
  }

  CorrectionRow? rowAt(int rowNumber) {
    for (final CorrectionRow r in rows) {
      if (r.parsed.rowNumber == rowNumber) return r;
    }
    return null;
  }

  bool get gateOpen => semester != null && blockingRows.isEmpty;
}
