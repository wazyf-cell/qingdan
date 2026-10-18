import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../domain/field_change.dart';
import '../domain/ids.dart';
import '../domain/op_log_entry.dart';
import '../domain/semester.dart';
import '../domain/time_table.dart';
import '../domain/timestamps.dart';
import 'op_log_writer.dart';
import 'row_diff.dart';

/// 学期 + 作息表 DAO（F28 / F30）。
///
/// 所有写方法自持事务，并在**同一事务**内追加 op-log（AGENTS.md 铁律）。
/// 作息明细按「节次」逐条 diff 记日志，因为 `time_detail` 是同步实体，
/// 合并粒度必须落在节上，不能整表记一条。
class SemesterDao {
  SemesterDao(this._db, {OpLogWriter? opLog})
      : _opLog = opLog ?? const OpLogWriter();

  final Database _db;
  final OpLogWriter _opLog;

  // ---- 学期 ----

  Future<List<Semester>> findAll() async {
    final List<Map<String, Object?>> rows =
        await _db.query('semesters', orderBy: 'created_time ASC');
    return [for (final Map<String, Object?> r in rows) Semester.fromMap(r)];
  }

  /// 当前激活学期（多学期之后仍然最多一个，但**每台设备各选各的**）。
  ///
  /// 查不到时自愈：把 `created_time` 最新的那一行置为当前。这不是多余的兜底——
  /// `is_active` 从 M6-D 起不再从同步来（远端来的学期一律 0），所以
  /// 「本地一个 active 都没有、但库里有学期」是**正常可达状态**（首次拉到学期、
  /// 手改过库、迁移边缘形状）。不选一个出来，`CoursePaneModel.load()` 拿到 null，
  /// 整个课表页空白，而用户看不出为什么。
  Future<Semester?> findActive() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'semesters',
      where: 'is_active = 1',
      limit: 1,
    );
    if (rows.isNotEmpty) return Semester.fromMap(rows.first);
    final List<Map<String, Object?>> newest = await _db.query(
      'semesters',
      orderBy: 'created_time DESC',
      limit: 1,
    );
    if (newest.isEmpty) return null;
    final Semester fallback = Semester.fromMap(newest.first);
    await setActiveSemester(fallback.id);
    return fallback;
  }

  /// 切换当前学期。**不写 op-log**：`is_active` 是设备本地列、上云时被剔除
  /// （见 `sync/local_only_columns.dart`），记意图只会产出一条被剔成空白的变更，
  /// 白跑一轮同步，还会让审计日志里出现「用户改了什么？什么都没改」。
  Future<void> setActiveSemester(String id) async {
    await _db.transaction((Transaction txn) async {
      await txn.rawUpdate(
          'UPDATE semesters SET is_active = 0 WHERE is_active = 1');
      await txn.rawUpdate(
          'UPDATE semesters SET is_active = 1 WHERE id = ?', <Object?>[id]);
    });
  }

  Future<Semester> insert({
    required String name,
    required DateTime firstWeekMonday,
    int totalWeeks = Semester.defaultTotalWeeks,
    String? id,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    // 「当前学期」必须只有一个，而 DDL 的列默认值是 1 —— 不显式决定就会出现
    // 第二个学期也 active=1，`findActive()` 拿到哪一行看 SQLite 心情（M6-D 多学期）。
    // 建学期时想切过去，调用方随后显式 `setActiveSemester`。
    final bool isFirst = (await _db.query('semesters', limit: 1)).isEmpty;
    final Semester semester = Semester(
      id: id ?? IdGenerator.next(),
      name: name,
      // 统一归一到该周的周一，并按纯日期存（§2.1）。
      firstWeekMonday: Semester.mondayOf(firstWeekMonday),
      totalWeeks: totalWeeks,
      isActive: isFirst,
      createdTime: now,
      modifiedTime: now,
    );
    await _db.transaction((Transaction txn) async {
      await txn.insert('semesters', semester.toMap());
      await _opLog.append(txn,
          entityType: OpLogEntityType.semester,
          entityId: semester.id,
          operation: OpLogOperation.create,
          changes: createChanges(semester.toMap()));
    });
    return semester;
  }

  Future<void> update(Semester semester) async {
    final Map<String, Object?>? before = await _row('semesters', semester.id);
    if (before == null) throw StateError('学期 ${semester.id} 不存在');
    // modified_time 不参与「有没有变化」的判定（同 CourseDao.update 的理由）。
    // `is_active` 与 `modified_time` 都不参与判定：前者是设备本地状态（M6-D），
    // 后者每次都是新值。更要命的是**写出去的 payload 里也不能带 `is_active`**——
    // 调用方拿的是加载时的旧快照，一旦它和库里的当前值不同，这条 UPDATE 就会
    // 把用户刚刚在学期面板里选的当前学期悄悄改回去。
    final List<FieldChange> changes = diffRowMaps(
      <String, Object?>{...before}
        ..remove('modified_time')
        ..remove('is_active'),
      <String, Object?>{...semester.toMap()}
        ..remove('modified_time')
        ..remove('is_active'),
    );
    if (changes.isEmpty) return;
    final Map<String, Object?> after = <String, Object?>{
      ...semester.toMap()..remove('is_active'),
      'modified_time': dateTimeToMs(DateTime.now().toUtc()),
    };
    await _db.transaction((Transaction txn) async {
      await txn.update('semesters', after,
          where: 'id = ?', whereArgs: <Object?>[semester.id]);
      await _opLog.append(txn,
          entityType: OpLogEntityType.semester,
          entityId: semester.id,
          operation: OpLogOperation.update,
          changes: changes);
    });
  }

  // ---- 作息表 ----

  /// 默认作息表（`semester_id` 为 NULL 的第一张，当前版本恒只有一张）。
  ///
  /// v6（M6-D）起模板库行也挂在 `semester_id IS NULL` 下（内置模板
  /// `builtin-college` 是其中之一），必须排除，否则「默认作息」会被模板
  /// 抢走身份（迁移 seed 的 created_time 早于一切运行期写入）。
  Future<TimeTable?> findDefaultTimetable() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'timetables',
      where: 'semester_id IS NULL AND is_template = 0',
      orderBy: 'created_time ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TimeTable(
      id: rows.first['id']! as String,
      name: rows.first['name']! as String,
      createdTime: msToDateTime(rows.first['created_time'] as int?),
      modifiedTime: msToDateTime(rows.first['modified_time'] as int?),
    );
  }

  Future<TimeTable> createTimetable({
    required String name,
    String? semesterId,
    String? id,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final TimeTable table = TimeTable(
      id: id ?? IdGenerator.next(),
      name: name,
      semesterId: semesterId,
      createdTime: now,
      modifiedTime: now,
    );
    await _db.transaction((Transaction txn) async {
      await txn.insert('timetables', table.toMap());
      await _opLog.append(txn,
          entityType: OpLogEntityType.timetable,
          entityId: table.id,
          operation: OpLogOperation.create,
          changes: createChanges(table.toMap()));
    });
    return table;
  }

  /// 某张作息表的全部节次，按节次升序。
  Future<List<TimeDetail>> findDetails(String timetableId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'time_details',
      where: 'timetable_id = ?',
      whereArgs: <Object?>[timetableId],
      orderBy: 'section ASC',
    );
    return [for (final Map<String, Object?> r in rows) TimeDetail.fromMap(r)];
  }

  /// 整表保存作息：按节次 diff，**同一事务**内删旧插新并逐节记 op-log。
  ///
  /// 节次仍存在的行**复用原 id**，否则同步侧会把「改了时间」看成「一删一增」。
  Future<void> replaceDetails(
    String timetableId,
    List<TimeDetail> next,
  ) async {
    final List<TimeDetail> current = await findDetails(timetableId);
    final Map<int, TimeDetail> oldBySection = <int, TimeDetail>{
      for (final TimeDetail d in current) d.section: d,
    };
    final DateTime now = DateTime.now().toUtc();
    await _db.transaction((Transaction txn) async {
      for (final TimeDetail d in current) {
        if (!next.any((TimeDetail n) => n.section == d.section)) {
          await txn.delete('time_details',
              where: 'id = ?', whereArgs: <Object?>[d.id]);
          await _opLog.append(txn,
              entityType: OpLogEntityType.timeDetail,
              entityId: d.id,
              operation: OpLogOperation.delete,
              changes: <FieldChange>[
                FieldChange(field: 'section', oldValue: d.section, newValue: null),
              ]);
        }
      }
      for (final TimeDetail n in next) {
        final TimeDetail? old = oldBySection[n.section];
        if (old == null) {
          final TimeDetail created = TimeDetail(
            id: n.id.isEmpty ? IdGenerator.next() : n.id,
            timetableId: timetableId,
            section: n.section,
            startMinutes: n.startMinutes,
            endMinutes: n.endMinutes,
            createdTime: now,
            modifiedTime: now,
          );
          await txn.insert('time_details', created.toMap());
          await _opLog.append(txn,
              entityType: OpLogEntityType.timeDetail,
              entityId: created.id,
              operation: OpLogOperation.create,
              changes: createChanges(created.toMap()));
          continue;
        }
        if (old.startMinutes == n.startMinutes &&
            old.endMinutes == n.endMinutes) {
          continue;
        }
        final TimeDetail kept = old.copyWith(
            startMinutes: n.startMinutes,
            endMinutes: n.endMinutes,
            modifiedTime: now);
        // modified_time 每次都会变，不能参与「有没有变化」的判定（同其它 DAO）。
        final List<FieldChange> changes = diffRowMaps(
          <String, Object?>{...old.toMap()}..remove('modified_time'),
          <String, Object?>{...kept.toMap()}..remove('modified_time'),
        );
        if (changes.isEmpty) continue;
        await txn.update('time_details', kept.toMap(),
            where: 'id = ?', whereArgs: <Object?>[old.id]);
        await _opLog.append(txn,
            entityType: OpLogEntityType.timeDetail,
            entityId: old.id,
            operation: OpLogOperation.update,
            changes: changes);
      }
    });
  }

  Future<Map<String, Object?>?> _row(String table, String id) async {
    final List<Map<String, Object?>> rows = await _db.query(table,
        where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }
}
