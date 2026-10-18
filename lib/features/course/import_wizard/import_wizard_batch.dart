// 校正界面的多选与批量操作（§4.3 规则 4 与规则 8）。
//
// 从模型里分出来有两个理由：模型合上它会过 300 行红线；而「选了哪些行 +
// 上一步批量处置的快照」本来就是一坨独立状态，单测也能直接打它。

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/domain/week_rule.dart';

import 'import_wizard_model.dart';
import 'import_wizard_types.dart';

class RowSelection {
  RowSelection(ImportWizardModel model) : _model = model;

  final ImportWizardModel _model;

  /// 已勾选的文件行号；非空即处于多选态。
  final Set<int> numbers = <int>{};

  /// 上一次批量处置的「行号 → 处置前状态」快照，供撤销（不弹窗轰炸）。
  Map<int, RowDisposition>? _undo;

  bool get active => numbers.isNotEmpty;
  bool get canUndo => _undo != null;

  void toggle(int rowNumber) {
    if (!numbers.remove(rowNumber)) numbers.add(rowNumber);
  }

  void selectAllListed() => numbers
    ..clear()
    ..addAll(<int>[for (final CorrectionRow r in _model.listed) r.parsed.rowNumber]);

  void clear() => numbers.clear();

  /// 批量忽略 / 批量删除：一次记一份快照，界面给一个「撤销」而不是确认弹窗。
  int applyDisposition(RowDisposition d) {
    final List<int> targets = <int>[...numbers];
    if (targets.isEmpty) return 0;
    _undo = <int, RowDisposition>{
      for (final int n in targets) n: _model.rowAt(n)!.disposition,
    };
    for (final int n in targets) {
      _model.rowAt(n)!.disposition = d;
    }
    numbers.clear();
    return targets.length;
  }

  /// 单行处置也记快照，这样「删错了」在两种入口下都能撤销。
  void rememberSingle(int rowNumber, RowDisposition before) =>
      _undo = <int, RowDisposition>{rowNumber: before};

  int undoLast() {
    final Map<int, RowDisposition>? snap = _undo;
    if (snap == null) return 0;
    snap.forEach((int n, RowDisposition d) => _model.rowAt(n)?.disposition = d);
    _undo = null;
    return snap.length;
  }

  /// 批量改周次 / 老师 / 地点：只作用于**解析成功**的行——✗ 行没有 Course，
  /// 得先修正或忽略，那是闸门（§3.1）的职责，这里不另发明一套规则。
  int edit({List<int>? weeks, String? teacher, String? location}) {
    int changed = 0;
    for (final int n in <int>[...numbers]) {
      final Course? c = _model.rowAt(n)?.parsed.course;
      if (c == null) continue;
      _model.applyEdit(n, _apply(c, weeks, teacher, location));
      changed++;
    }
    numbers.clear();
    return changed;
  }
}

/// 批量改写后的新行。**不能走 copyWith**：它把 null 当「不改」，于是
/// 「留空即清空」永远清不掉；而周次变了又必须重算 UID（§3.5：改周次 = 一删一增），
/// 否则导入会按旧 UID 去重，把改了周次的课误当成已有课更新掉。
Course _apply(Course c, List<int>? weeks, String? teacher, String? location) {
  final List<int> nextWeeks = weeks == null ? c.weeks : Course.normalizeWeeks(weeks);
  return Course(
    id: c.id,
    uid: courseUidOf(
        name: c.name,
        weekday: c.weekday,
        startSection: c.startSection,
        endSection: c.endSection,
        weeks: nextWeeks),
    name: c.name,
    weekday: c.weekday,
    startSection: c.startSection,
    endSection: c.endSection,
    weeks: nextWeeks,
    semesterId: c.semesterId,
    teacher: teacher == null ? c.teacher : Course.blankToNull(teacher),
    location: location == null ? c.location : Course.blankToNull(location),
    rawWeeksText: weeks == null ? c.rawWeeksText : formatWeeks(nextWeeks),
    origin: c.origin,
    importBatchId: c.importBatchId,
    deleted: c.deleted,
    createdTime: c.createdTime,
    modifiedTime: c.modifiedTime,
  );
}
