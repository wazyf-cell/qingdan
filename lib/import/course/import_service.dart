// 导入服务：把校正后的行算成「落库计划」，再交给 `CourseDao.applyImport` 单事务写入。
//
// 三种模式的语义见 `方案设计-课表域.md` §3.5，闸门见 §3.1。本文件不碰 UI、
// 不开事务：算计划是纯查，写全部下沉到 DAO 的同一个事务里（不留半截数据）。

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/domain/ids.dart';
import 'package:qingdan/data/course_dao.dart';

/// 导入模式（§3.5 表）。
enum ImportMode {
  /// UID 已存在 → 用文件值覆盖非键字段；库里有、文件里没有的**不动**。
  merge,

  /// 先软删该学期内 `origin == import` 的全部课（手动课不受影响），再全量插入。
  overwrite,

  /// 只插库里没有的 UID，其余全部跳过。
  appendOnly,
}

String describeImportMode(ImportMode mode) => switch (mode) {
      ImportMode.merge => '合并',
      ImportMode.overwrite => '覆盖',
      ImportMode.appendOnly => '仅新增',
    };

/// 落库计划：步 5 的红字提示、汇总页都只读它，不重复查库。
class ImportPlan {
  ImportPlan({
    required this.mode,
    required this.insert,
    required this.update,
    required this.skipped,
    required this.duplicated,
    required this.willRemoveImported,
    required this.activeManualCount,
  });

  final ImportMode mode;

  /// 新插入的行（覆盖模式下 = 文件全部行，§3.5「先软删再全量插入」）。
  final List<Course> insert;

  /// UID 已存在 → 只改非键字段的行（覆盖 / 仅新增模式下恒空）。
  final List<Course> update;

  /// 仅新增模式下被跳过的已存在行。
  final List<Course> skipped;

  /// **文件内**同 UID 的重复行（§3.4「完全相同的行静默去重」，只保留第一条）。
  final List<Course> duplicated;

  /// 覆盖模式将被软删的现有导入课条数（红字提示用，不做逐条审）。
  final int willRemoveImported;

  /// 同学期手动创建的课数（红字里那句「手动添加的 M 条不受影响」）。
  final int activeManualCount;
}

class ImportService {
  ImportService(this._courses);

  final CourseDao _courses;

  /// 算计划。[rows] 必须是**已过闸门**的行（✗ 行由校正界面挡在步 4，§3.1）。
  Future<ImportPlan> plan({
    required List<Course> rows,
    required String semesterId,
    required ImportMode mode,
  }) async {
    // ① 文件内先去重（UID 相同的只留第一条）。
    final Set<String> seen = <String>{};
    final List<Course> fresh = <Course>[];
    final List<Course> duplicated = <Course>[];
    for (final Course row in rows) {
      final String uid = _uidOf(row);
      if (!seen.add(uid)) {
        duplicated.add(row);
        continue;
      }
      fresh.add(row.copyWith(uid: uid, semesterId: semesterId));
    }

    // ② 与库比对。覆盖模式不做 diff：旧的一律软删、新的一律插入，
    //    这样「改周次」如实表现为一删一增（§3.5 明说的代价）。
    final List<Course> insert = <Course>[];
    final List<Course> update = <Course>[];
    final List<Course> skipped = <Course>[];
    if (mode == ImportMode.overwrite) {
      insert.addAll(fresh);
    } else {
      for (final Course row in fresh) {
        final List<Course> existing =
            await _courses.findByUid(row.uid, semesterId: semesterId);
        if (existing.isEmpty) {
          insert.add(row);
        } else if (mode == ImportMode.appendOnly) {
          skipped.add(row);
        } else {
          // 以库中行为底，只覆盖非键字段——id / created_time / 键字段都得保住。
          update.add(existing.first.copyWith(
            name: row.name,
            teacher: row.teacher,
            location: row.location,
            rawWeeksText: row.rawWeeksText,
          ));
        }
      }
    }

    final List<Course> active =
        await _courses.findActive(semesterId: semesterId);
    return ImportPlan(
      mode: mode,
      insert: insert,
      update: update,
      skipped: skipped,
      duplicated: duplicated,
      willRemoveImported: active
          .where((Course c) => c.origin == CourseOrigin.import)
          .length,
      activeManualCount:
          active.where((Course c) => c.origin == CourseOrigin.manual).length,
    );
  }

  /// 落库：整批一个事务，批次行同事务写入（计数由 DAO 按实际写入量填）。
  Future<({int inserted, int updated, int skipped, int removed})> apply({
    required ImportPlan plan,
    required String semesterId,
    required String fileName,
  }) async {
    final String batchId = IdGenerator.next();
    Course stamp(Course c) =>
        c.copyWith(origin: CourseOrigin.import, importBatchId: batchId);
    final ({int inserted, int updated, int removed}) written =
        await _courses.applyImport(
      insert: <Course>[for (final Course c in plan.insert) stamp(c)],
      update: <Course>[for (final Course c in plan.update) stamp(c)],
      softDeleteImportedFirst: plan.mode == ImportMode.overwrite,
      semesterId: semesterId,
      skippedCount: plan.skipped.length + plan.duplicated.length,
      batch: ImportBatch(
        id: batchId,
        fileName: fileName,
        importedAt: DateTime.now().toUtc(),
      ),
    );
    return (
      inserted: written.inserted,
      updated: written.updated,
      skipped: plan.skipped.length + plan.duplicated.length,
      removed: written.removed,
    );
  }

  /// 键字段任一变了 UID 就变（§3.5：改周次 = 一删一增，改老师/地点 = 更新）。
  static String _uidOf(Course c) => c.uid.isNotEmpty
      ? c.uid
      : courseUidOf(
          name: c.name,
          weekday: c.weekday,
          startSection: c.startSection,
          endSection: c.endSection,
          weeks: c.weeks,
        );
}
