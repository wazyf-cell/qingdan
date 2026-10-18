// 导入向导模型 · 步 5（确认与落库）的状态（§十二.2 从
// `import_wizard_model.dart` 按职责搬出：搬家不改行为，方法体逐字一致）。

import 'package:flutter/foundation.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/import/course/import_service.dart';

/// 步 5：模式选择、计划、唯一写库入口。落库只发生在 [finish]，
/// 且经 ImportService 的单个事务；错误原文留在 [finishError] 给界面显示。
mixin WizardConfirmSteps on ChangeNotifier {
  ImportService get importer;
  Semester? get semester;
  String? get fileName;
  List<Course> get importableCourses;

  // ---- 步 5 ----
  ImportMode mode = ImportMode.merge;

  /// 库里已有导入课 → 首次导入要**隐藏模式选择**（§3.1:166）。
  bool hadImportedBefore = false;
  ImportPlan? plan;
  ({int inserted, int updated, int skipped, int removed})? result;
  String? finishError;

  /// 导入时把**选中的那个学期**的总周数抬到了这个值；null = 没抬。
  /// 汇总页据此多打一行（M6-D §7.5：目标学期由步 3 下拉决定，不再是 active）。
  int? weeksRaisedTo;

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
}
