// 导入向导的状态机（`方案设计-课表域-界面.md` §4.2 五步 + `课表域.md` §3.1 闸门）。
//
// 五步的**状态与业务逻辑全在这里**，step 文件只做布局壳（§五 要求的「5 个
// StepWidget 的状态与业务逻辑共用，布局壳分端」）。本文件不碰 IO、不碰界面：
// 文件字节由步 1 的壳读好递进来，落库只发生在 [finish]，且经 ImportService
// 的单个事务。

import 'package:flutter/foundation.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/import/course/column_mapping.dart';
import 'package:qingdan/import/course/course_row_parser.dart';
import 'package:qingdan/import/course/import_service.dart';
import 'package:qingdan/import/course/schedule_file.dart';
import 'package:qingdan/import/course/wakeup_schedule_file.dart';

import 'import_wizard_batch.dart';
import 'import_wizard_types.dart';

/// 导入向导模型。生命周期 = 一次向导会话（关闭即弃，不留状态）。
class ImportWizardModel extends ChangeNotifier {
  ImportWizardModel(
      {required this.importer,
      this.semester,
      this.details = const <TimeDetail>[]});

  final ImportService importer;

  /// 当前生效的学期（步 3 可新建；为 null 时步 3 强制填写）。
  Semester? semester;
  List<TimeDetail> details;

  WizardStep step = WizardStep.file;
  String? fileError;
  String? finishError;

  // ---- 步 1 ----
  String? fileName;
  Uint8List? _bytes;
  ScheduleTable? _table;

  /// WakeUp 导出顺带带的学期与作息（其它来源为 null）。步 3 用它**预填 +
  /// 用户点「采纳」才写**，不静默覆盖已有学期。
  WakeupMeta? wakeupMeta;

  // ---- 步 2 ----
  ColumnMapping? mapping;

  // ---- 步 4 ----
  final List<CorrectionRow> rows = <CorrectionRow>[];

  // ---- 步 5 ----
  ImportMode mode = ImportMode.merge;

  /// 库里已有导入课 → 首次导入要**隐藏模式选择**（§3.1:166）。
  bool hadImportedBefore = false;
  ImportPlan? plan;
  ({int inserted, int updated, int skipped, int removed})? result;

  bool get hasFile => _table != null;
  ScheduleTable? get table => _table;
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
  /// 导入完拿它去抬学期总周数（2026-10-18 定案）：周数是**翻页上限**，
  /// 不抬的话排在学期外面的课查得到却翻不到，用户看到的就是「只到 16 周」。
  int get maxImportedWeek {
    int top = 0;
    for (final Course c in importableCourses) {
      if (c.weeks.isNotEmpty && c.weeks.last > top) top = c.weeks.last;
    }
    return top;
  }

  /// 导入时把学期总周数抬到了这个值；null = 没抬。汇总页据此多打一行。
  int? weeksRaisedTo;

  // ================= 步 1：文件 =================

  /// [fileName] 只作展示与真实类型提示，**判类型看字节**（用户常改扩展名）。
  void loadFile({required String fileName, required Uint8List bytes}) {
    this.fileName = fileName;
    _bytes = bytes;
    fileError = null;
    wakeupMeta = isWakeupSchedule(bytes) ? readWakeupMeta(bytes) : null;
    try {
      final ScheduleTable t = readScheduleTable(bytes, fileName: fileName);
      if (t.isEmpty) {
        fileError = '文件里没有任何数据行';
        _table = null;
      } else {
        _table = t;
      }
    } on ScheduleFileException catch (e) {
      fileError = e.message;
      _table = null;
    }
    notifyListeners();
  }

  /// 已经解析好的表（教务系统抓取那条链）：跳过「字节 → 表」这一步，
  /// 从列映射开始走同一条向导，校正与三模式落库完全复用。
  void loadTable({required String fileName, required ScheduleTable table}) {
    this.fileName = fileName;
    _bytes = null;
    fileError = null;
    if (table.isEmpty) {
      fileError = '抓取结果里没有数据行';
      _table = null;
    } else {
      _table = table;
    }
    notifyListeners();
  }

  /// 界面上手动切换编码重读（§3.1:162「允许手动切换重读」）。
  void reloadWith(FileEncoding encoding) {
    final Uint8List? bytes = _bytes;
    if (bytes == null) return;
    try {
      _table =
          readScheduleTable(bytes, fileName: fileName, forceEncoding: encoding);
      fileError = null;
    } on ScheduleFileException catch (e) {
      fileError = e.message;
      _table = null;
    }
    notifyListeners();
  }

  // ================= 步 2：列映射 =================

  void guessMapping() {
    final ScheduleTable? t = _table;
    if (t == null || mapping != null) return;
    mapping = guessColumnMapping(t);
    notifyListeners();
  }

  String? assignColumn(int index, CourseField field) {
    final String? notice = mapping?.assign(index, field);
    notifyListeners();
    return notice;
  }

  bool get mappingReady => mapping?.canImport ?? false;

  // ================= 步 3：学期与作息 =================

  bool get setupReady => semester != null;

  void adoptSemester(Semester? s, List<TimeDetail> timetable) {
    semester = s;
    details = timetable;
    notifyListeners();
  }

  /// 进入步 4：按当前映射与学期作息解析。**每次进入都重算**，所以从步 5 回跳
  /// 到步 2 改过映射后，旧校正在这里自然作废（§3.1:168）。
  void buildRows() {
    final ScheduleTable? t = _table;
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

  /// 多选与批量操作的状态与动作都在 [RowSelection]（文件级拆分只为 300 行红线）。
  /// 下面几个是界面用的薄委托：调完统一 notifyListeners。
  late final RowSelection selection = RowSelection(this);

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

  // ================= 步 5：确认与落库 =================

  Future<void> preparePlan() async {
    final Semester? s = semester;
    if (s == null) return;
    plan = await importer.plan(
        rows: importableCourses, semesterId: s.id, mode: mode);
    // 「首次导入」= 这个学期库里还没有导入来的课（§3.1:166 隐藏模式选择）。
    hadImportedBefore = plan!.willRemoveImported > 0;
    notifyListeners();
  }

  /// 换模式必须重算计划：三种模式对同一批行的 insert/update/skip 划分不同。
  Future<void> setMode(ImportMode next) async {
    if (mode == next) return;
    mode = next;
    await preparePlan();
  }

  /// 唯一写库入口。失败不静默：错误原文留在 [finishError] 给界面显示。
  Future<bool> finish() async {
    final ImportPlan? p = plan;
    final Semester? s = semester;
    if (p == null || s == null) return false;
    try {
      result = await importer.apply(
          plan: p, semesterId: s.id, fileName: fileName ?? '未命名文件');
      // 成功也要通知：否则步 5 停在「开始导入」，切不到汇总页。
      notifyListeners();
      return true;
    } on Object catch (e) {
      finishError = '$e';
      notifyListeners();
      return false;
    }
  }

  /// 回跳。作废提示由外壳在跳转前弹确认（`import_wizard.dart` 的 _jumpTo），
  /// 这里只负责切步——真要回到映射步，步 4 的行会在重新前进时整体重算。
  void backTo(WizardStep target) {
    step = target;
    notifyListeners();
  }

  void go(WizardStep target) {
    step = target;
    notifyListeners();
  }
}
