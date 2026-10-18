// 导入向导的状态机（`方案设计-课表域-界面.md` §4.2 五步 + `课表域.md` §3.1 闸门）。
//
// 五步的**状态与业务逻辑按职责拆成 mixin**（§十二.2：本文件曾 332 行触
// 300 红线，2026-10-19 按职责搬家——行为逐字未变）：
//   * `import_wizard_model_file.dart`    步 1 文件 + 步 2 列映射
//   * `import_wizard_model_correct.dart` 步 3 装配 + 步 4 校正/批量
//   * `import_wizard_model_confirm.dart` 步 5 计划与落库
// 本文件只留核心状态（学期/作息/当前步）与导航。step 文件只做布局壳；
// 本文件不碰 IO、不碰界面：文件字节由步 1 的壳读好递进来，落库只发生在
// `finish()`，且经 ImportService 的单个事务。

import 'package:flutter/foundation.dart';

import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/import/course/import_service.dart';

import 'import_wizard_batch.dart';
import 'import_wizard_model_confirm.dart';
import 'import_wizard_model_correct.dart';
import 'import_wizard_model_file.dart';
import 'import_wizard_types.dart';

/// 导入向导模型。生命周期 = 一次向导会话（关闭即弃，不留状态）。
class ImportWizardModel extends ChangeNotifier
    with WizardFileSteps, WizardCorrectSteps, WizardConfirmSteps {
  ImportWizardModel(
      {required this.importer,
      this.semester,
      this.details = const <TimeDetail>[]});

  @override
  final ImportService importer;

  /// 步 3 选定的**导入目标学期**（多学期后由 `adopt-semester` 下拉决定，
  /// 不一定是 active 学期；为 null 时步 3 强制填写）。
  /// 步 4 解析、步 5 落库、扩周数全部跟着它走（M6-D §7.5）。
  @override
  Semester? semester;

  /// 目标学期的作息节次（渲染与超界警告用）。
  @override
  List<TimeDetail> details;

  @override
  WizardStep step = WizardStep.file;

  /// 多选与批量操作的状态与动作都在 [RowSelection]（文件级拆分只为 300 行红线）。
  @override
  late final RowSelection selection = RowSelection(this);

  // ================= 步 3：学期与作息 =================

  bool get setupReady => semester != null;

  void adoptSemester(Semester? s, List<TimeDetail> timetable) {
    semester = s;
    details = timetable;
    notifyListeners();
  }

  // ================= 导航 =================

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
