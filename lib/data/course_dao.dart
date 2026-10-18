import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../domain/course.dart';
import '../domain/course_freshness.dart';
import '../domain/field_change.dart';
import '../domain/ids.dart';
import '../domain/op_log_entry.dart';
import '../domain/timestamps.dart';
import 'course_dao_queries.dart';
import 'op_log_writer.dart';
import 'row_diff.dart';

/// 课程 DAO（F28 / F29 / F31）——**写侧**。
///
/// 写方法自持事务并在同一事务内记 op-log。`import_batches` 是本地簿记，
/// **不记 op-log、不参与同步**（2026-10-10 定案 3）。
/// 只读查询在 `course_dao_queries.dart`（本文件触 300 行红线后按读/写拆的）。
class CourseDao {
  CourseDao(this._db, {OpLogWriter? opLog})
      : _opLog = opLog ?? const OpLogWriter(),
        _queries = CourseQueries(_db);

  final Database _db;
  final OpLogWriter _opLog;
  final CourseQueries _queries;

  // ---- 只读转发：签名不变，调用方（用例层 / 同步 / 测试）无需改动 ----

  Future<List<Course>> findActive({String? semesterId, int? weekday}) =>
      _queries.findActive(semesterId: semesterId, weekday: weekday);

  Future<List<Course>> findOnWeek(int week, {String? semesterId}) =>
      _queries.findOnWeek(week, semesterId: semesterId);

  Future<List<Course>> findByUid(String uid, {String? semesterId}) =>
      _queries.findByUid(uid, semesterId: semesterId);

  Future<Course?> findById(String id) => _queries.findById(id);

  Future<int> countActive({String? semesterId}) =>
      _queries.countActive(semesterId: semesterId);

  /// 最近 [limit] 次导入批次（A8 历史面板），每条带学期归属（M6-D §八）。
  Future<List<ImportBatchEntry>> recentBatches({int limit = 10}) =>
      _queries.recentBatches(limit: limit);

  /// **该学期**的最近一次导入批次（M6-D §八）。老批次（semester_id NULL）
  /// 不属于任何学期，不会从这里返回。
  Future<ImportBatchEntry?> latestBatch(String semesterId) =>
      _queries.latestBatch(semesterId);

  /// 本学期课程的最后编辑时刻，无记录返回 null（A8）。
  Future<DateTime?> lastCourseModified(String semesterId) =>
      _queries.lastCourseModified(semesterId);

  // ---- 写侧 ----

  Future<Course> insert(Course course) async {
    final Course row = _newRowForInsert(course);
    await _db.transaction((Transaction txn) => _writeInsert(txn, row));
    return row;
  }

  /// 补全「新插入一行」必须由库来定的字段（id 与两个时间戳）。
  Course _newRowForInsert(Course course) {
    final DateTime now = DateTime.now().toUtc();
    return Course(
      id: course.id.isEmpty ? IdGenerator.next() : course.id,
      uid: course.uid,
      name: course.name,
      teacher: course.teacher,
      location: course.location,
      weekday: course.weekday,
      startSection: course.startSection,
      endSection: course.endSection,
      weeks: course.weeks,
      rawWeeksText: course.rawWeeksText,
      semesterId: course.semesterId,
      origin: course.origin,
      importBatchId: course.importBatchId,
      deleted: course.deleted,
      createdTime: now,
      modifiedTime: now,
    );
  }

  /// 行级写入（不含事务）：`insert` 与导入的 `applyImport` 共用同一份实现，
  /// 免得两处各写一遍 op-log 而漂移。`txn` 取 `DatabaseExecutor`——
  /// `Transaction` 与 `Database` 都实现它，所以既能进事务也能裸跑。
  Future<void> _writeInsert(DatabaseExecutor txn, Course row) async {
    await txn.insert('courses', row.toMap());
    await _opLog.append(txn,
        entityType: OpLogEntityType.course,
        entityId: row.id,
        operation: OpLogOperation.create,
        changes: createChanges(row.toMap()));
  }

  Future<void> update(Course course) =>
      _db.transaction((Transaction txn) => _writeUpdate(txn, course));

  /// 有变化才写：空更新既不记 op-log，也不把字段级 LWW 的时间戳无谓推后。
  /// 返回实际写入的字段数（0 = 没动）。
  Future<int> _writeUpdate(DatabaseExecutor txn, Course course) async {
    final List<Map<String, Object?>> before = await txn.query('courses',
        where: 'id = ?', whereArgs: <Object?>[course.id], limit: 1);
    if (before.isEmpty) throw StateError('课程 ${course.id} 不存在');
    // `modified_time` 每次都会变，不能参与「有没有变化」的判定。
    final List<FieldChange> changes = diffRowMaps(
      <String, Object?>{...before.first}..remove('modified_time'),
      <String, Object?>{...course.toMap()}..remove('modified_time'),
    );
    if (changes.isEmpty) return 0;
    final Map<String, Object?> after = <String, Object?>{
      ...course.toMap(),
      'modified_time': dateTimeToMs(DateTime.now().toUtc()),
    };
    await txn.update('courses', after,
        where: 'id = ?', whereArgs: <Object?>[course.id]);
    await _opLog.append(txn,
        entityType: OpLogEntityType.course,
        entityId: course.id,
        operation: OpLogOperation.update,
        changes: changes);
    return changes.length;
  }

  /// 软删除（课程不进回收站，只是不再显示；同步侧按 update 记）。
  ///
  /// 对用户等于**永久删除**：回收站只管任务，课程没有找回入口，
  /// 所以 UI 的确认框必须写清「无法找回」（A6）。
  Future<void> softDelete(String id) async {
    final Course? existing = await findById(id);
    if (existing == null || existing.deleted) return;
    final Map<String, Object?> after = <String, Object?>{
      ...existing.toMap(),
      'deleted': 1,
      'modified_time': dateTimeToMs(DateTime.now().toUtc()),
    };
    await _db.transaction((Transaction txn) async {
      await txn.update('courses', after,
          where: 'id = ?', whereArgs: <Object?>[id]);
      await _opLog.append(txn,
          entityType: OpLogEntityType.course,
          entityId: id,
          operation: OpLogOperation.update,
          changes: <FieldChange>[
            const FieldChange(field: 'deleted', oldValue: 0, newValue: 1),
          ]);
    });
  }

  /// 「覆盖导入」用：软删该学期内 `origin == import` 的课，**不动手动创建的课**。
  ///
  /// 返回被软删的条数，供结果汇总页与红字提示（§3.5）。
  Future<int> softDeleteImported({String? semesterId}) => _db
      .transaction<int>((Transaction txn) => _writeSoftDeleteImported(txn, semesterId));

  Future<int> _writeSoftDeleteImported(
      DatabaseExecutor txn, String? semesterId) async {
    final List<Course> targets = await readActiveCourses(txn, semesterId);
    final List<Course> imported = targets
        .where((Course c) => c.origin == CourseOrigin.import)
        .toList(growable: false);
    if (imported.isEmpty) return 0;
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final Course c in imported) {
      await txn.update('courses', <String, Object?>{
        ...c.toMap(),
        'deleted': 1,
        'modified_time': now,
      }, where: 'id = ?', whereArgs: <Object?>[c.id]);
      await _opLog.append(txn,
          entityType: OpLogEntityType.course,
          entityId: c.id,
          operation: OpLogOperation.update,
          changes: <FieldChange>[
            const FieldChange(field: 'deleted', oldValue: 0, newValue: 1),
          ]);
    }
    return imported.length;
  }

  /// 导入落库的**唯一**写入点：三种模式共用，整批一个事务
  /// （§3.1「单事务内删旧插新」，中途异常不留半截数据）。
  ///
  /// 计划由 `import_service` 算好后传进来（本方法不做 UID 判定），DAO 只管写。
  /// [updated] 只统计**真的有字段变化**的行——空更新不计。
  Future<({int inserted, int updated, int removed})> applyImport({
    required List<Course> insert,
    required List<Course> update,
    required bool softDeleteImportedFirst,
    String? semesterId,
    int skippedCount = 0,
    ImportBatch? batch,
  }) =>
      _db.transaction<({int inserted, int updated, int removed})>(
          (Transaction txn) async {
        // 批次行**必须先写**：`courses.import_batch_id` 外键指向它，晚一步就
        // 是 FK 787（M3 的 kEntityTypes 顺序坑同源）。计数最后在同一事务里回填。
        // `semester_id`（M6-D §八，v6 列）在这里盖上：[ImportBatch.toMap] 不带它
        // （`import_batches` 不同步，不许把学期归属混进序列化路径）。
        final Map<String, Object?>? batchRow = batch == null
            ? null
            : <String, Object?>{...batch.toMap(), 'semester_id': semesterId};
        if (batchRow != null) await txn.insert('import_batches', batchRow);
        final int removed = softDeleteImportedFirst
            ? await _writeSoftDeleteImported(txn, semesterId)
            : 0;
        int updated = 0;
        for (final Course c in update) {
          if (await _writeUpdate(txn, c) > 0) updated++;
        }
        for (final Course c in insert) {
          await _writeInsert(txn, _newRowForInsert(c));
        }
        if (batch != null && batchRow != null) {
          batch
            ..countImported = insert.length
            ..countUpdated = updated
            ..countSkipped = skippedCount;
          await txn.update('import_batches', batchRow,
              where: 'id = ?', whereArgs: <Object?>[batch.id]);
        }
        return (inserted: insert.length, updated: updated, removed: removed);
      });

  // ---- 导入批次（本地簿记）----

  /// 单独记一批（测试与「先建批次再逐行挂」的路径用）；正常导入走
  /// [applyImport]，批次行与课程行在同一事务写。
  /// [semesterId] 缺省 null = 老形状（学期归属未知，历史面板显示「（学期未知）」）。
  Future<ImportBatch> insertBatch(ImportBatch batch, {String? semesterId}) async {
    await _db.insert('import_batches',
        <String, Object?>{...batch.toMap(), 'semester_id': semesterId});
    return batch;
  }
}
