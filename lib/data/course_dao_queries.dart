import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../domain/course.dart';
import '../domain/course_freshness.dart';
import '../domain/timestamps.dart';

/// `courses` / `import_batches` 的**只读**查询（M6-A A8）。
///
/// 拆出来不是为了换职责，而是 `course_dao.dart` 触 300 行红线：写侧要连着
/// op-log 一起看，读侧单独成文后两边都能一次读完。
/// 读逻辑仍然允许进事务（[readActiveCourses] 收 `DatabaseExecutor`）。
class CourseQueries {
  CourseQueries(this._db);

  final Database _db;

  /// 未删除的课程，按星期 + 起始节 + 课名排序。[semesterId] 为空则不限学期。
  Future<List<Course>> findActive({String? semesterId, int? weekday}) =>
      readActiveCourses(_db, semesterId, weekday: weekday);

  /// 第 [week] 周要上的课。
  ///
  /// 周次在库里是 JSON 数组字符串，**不能用 `LIKE '%3%'` 过滤**（会把第 3 周
  /// 和第 13、23 周一起捞出来），所以先按学期+星期捞、再在 Dart 里 `contains`。
  Future<List<Course>> findOnWeek(int week, {String? semesterId}) async {
    final List<Course> all = await findActive(semesterId: semesterId);
    return all.where((Course c) => c.isOn(week)).toList(growable: false);
  }

  Future<List<Course>> findByUid(String uid, {String? semesterId}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'courses',
      where: 'uid = ? AND deleted = 0'
          '${semesterId == null ? '' : ' AND semester_id = ?'}',
      whereArgs: <Object?>[uid, ?semesterId],
    );
    return [for (final Map<String, Object?> r in rows) Course.fromMap(r)];
  }

  Future<Course?> findById(String id) async {
    final List<Map<String, Object?>> rows = await _db.query('courses',
        where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : Course.fromMap(rows.first);
  }

  /// 未删除课程总数（今日课空态判断用）。
  Future<int> countActive({String? semesterId}) async {
    final List<Map<String, Object?>> result = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM courses WHERE deleted = 0'
      '${semesterId == null ? '' : ' AND semester_id = ?'}',
      <Object?>[?semesterId],
    );
    return result.first['n']! as int;
  }

  /// 最近 [limit] 次导入批次，新的在前（A8 历史面板，M6-D §八 带学期归属）。
  ///
  /// LEFT JOIN `semesters` 带出学期名：老批次 `semester_id IS NULL`、
  /// 或学期已删，都拿不到名字——历史面板显示「（学期未知）」，
  /// **不许假装它们属于当前学期**。
  Future<List<ImportBatchEntry>> recentBatches({int limit = 10}) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT b.*, s.name AS semester_name FROM import_batches b '
      'LEFT JOIN semesters s ON s.id = b.semester_id '
      'ORDER BY b.imported_at DESC LIMIT ?',
      <Object?>[limit],
    );
    return [for (final Map<String, Object?> r in rows) ImportBatchEntry.fromRow(r)];
  }

  /// **该学期**最近一次导入批次（M6-D §八：A8 的 `latestBatch()` 补上学期维度）。
  ///
  /// 只认 `semester_id = ?` 的行——老批次（NULL）不属于任何学期，导进 A 学期
  /// 的批次也不得让 B 学期显示「N 分钟前导入」。没有则返回 null。
  Future<ImportBatchEntry?> latestBatch(String semesterId) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT b.*, s.name AS semester_name FROM import_batches b '
      'LEFT JOIN semesters s ON s.id = b.semester_id '
      'WHERE b.semester_id = ? ORDER BY b.imported_at DESC LIMIT 1',
      <Object?>[semesterId],
    );
    return rows.isEmpty ? null : ImportBatchEntry.fromRow(rows.first);
  }

  /// 本学期未删除课程里最晚的一次编辑时刻（`MAX(modified_time)`）。
  ///
  /// 没有课（或课的时间戳全为 NULL，老数据同步来的那种）返回 null。
  Future<DateTime?> lastCourseModified(String semesterId) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT MAX(modified_time) AS m FROM courses '
      'WHERE semester_id = ? AND deleted = 0',
      <Object?>[semesterId],
    );
    return msToDateTime(rows.isEmpty ? null : rows.first['m'] as int?);
  }
}

/// 「未删除课程」的唯一读实现：事务内（`applyImport`）与事务外共用一份。
Future<List<Course>> readActiveCourses(
    DatabaseExecutor executor, String? semesterId,
    {int? weekday}) async {
  final List<String> where = <String>['deleted = 0'];
  final List<Object?> args = <Object?>[];
  if (semesterId != null) {
    where.add('semester_id = ?');
    args.add(semesterId);
  }
  if (weekday != null) {
    where.add('weekday = ?');
    args.add(weekday);
  }
  final List<Map<String, Object?>> rows = await executor.query('courses',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'weekday ASC, start_section ASC, name ASC');
  return [for (final Map<String, Object?> r in rows) Course.fromMap(r)];
}
