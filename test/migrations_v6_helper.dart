/// 迁移 v6 测试的共用夹具（自 migrations_v6_test.dart 拆出；非 `_test` 文件，
/// flutter test 不直接执行）。
///
/// 升级验收与幂等重跑两份测试都要在磁盘上造 v4/v5 形状的旧库（内存库做不到
/// 「关开重放 onUpgrade」），插行辅助与查询快照两边共用，不在测试文件里复制。
library;

import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/default_timetable.dart';

/// 磁盘库（可关开重放 onUpgrade，内存库做不到）。
Future<Database> openDisk(String path, int version) =>
    databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (Database db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database db, int v) =>
            runMigrations(db, fromVersion: 0, toVersion: v),
        onUpgrade: (Database db, int from, int to) =>
            runMigrations(db, fromVersion: from, toVersion: to),
      ),
    );

Future<void> insertSemester(Database db,
    {String id = 's1', int isActive = 1, int createdTime = 1000}) async {
  await db.insert('semesters', <String, Object?>{
    'id': id,
    'name': '学期$id',
    'first_week_monday': DateTime.utc(2025, 9, 1).millisecondsSinceEpoch,
    'total_weeks': 20,
    'is_active': isActive,
    'created_time': createdTime,
    'modified_time': createdTime,
  });
}

Future<void> insertTimetable(Database db,
    {String id = 't1', String? semesterId}) async {
  await db.insert('timetables', <String, Object?>{
    'id': id,
    'name': '默认作息',
    'semester_id': semesterId,
    'created_time': 2000,
    'modified_time': 2000,
  });
}

Future<void> insertDetails(Database db, String timetableId,
    {int count = 12}) async {
  for (int i = 1; i <= count; i++) {
    await db.insert('time_details', <String, Object?>{
      'id': '${timetableId}_d$i',
      'timetable_id': timetableId,
      'section': i,
      'start_minutes': 480 + (i - 1) * 55,
      'end_minutes': 525 + (i - 1) * 55,
    });
  }
}

Future<void> insertCourse(Database db, String id) async {
  await db.insert('courses', <String, Object?>{
    'id': id,
    'uid': 'u_$id',
    'name': '高等数学$id',
    'weekday': 1,
    'start_section': 1,
    'end_section': 2,
    'weeks': '[1,2]',
    'semester_id': 's1',
  });
}

/// 造一个 v5 形状的库：1 active 学期 + 1 张匿名作息（semester_id NULL）
/// + 12 行 time_details + 3 门课。
Future<void> buildV5DiskDb(String path,
    {bool withActiveSemester = true,
    bool anonymousTimetable = true,
    bool withDetails = true}) async {
  final Database db = await openDisk(path, 5);
  if (withActiveSemester) await insertSemester(db);
  if (anonymousTimetable) await insertTimetable(db, semesterId: null);
  if (anonymousTimetable && withDetails) await insertDetails(db, 't1');
  if (withActiveSemester) {
    for (final String c in <String>['c1', 'c2', 'c3']) {
      await insertCourse(db, c);
    }
  }
  await db.close();
}

Future<List<Map<String, Object?>>> builtInRows(Database db) => db.query(
      'time_details',
      where: 'timetable_id = ?',
      whereArgs: <Object?>[kBuiltInTimetableId],
      orderBy: 'section ASC',
    );
