import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/data/course_dao.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/data/semester_dao.dart';
import 'package:qingdan/data/subtask_dao.dart';
import 'package:qingdan/data/tag_dao.dart';
import 'package:qingdan/data/task_dao.dart';
import 'package:qingdan/data/task_list_dao.dart';

/// DAO 测试共享环境（自 dao_test.dart 拆出）：
/// FFI 初始化 + 每条用例独立的内存库（迁移到最新版 + 外键开启）+ 六个 DAO。

/// 在 main() 的 setUpAll 中调用一次。
void ensureSqfliteFfi() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// 一条用例的完整数据层环境。
class DaoTestDb {
  DaoTestDb._(this.db)
      : listDao = TaskListDao(db),
        taskDao = TaskDao(db),
        subtaskDao = SubtaskDao(db),
        tagDao = TagDao(db),
        semesterDao = SemesterDao(db),
        courseDao = CourseDao(db);

  final Database db;
  final TaskListDao listDao;
  final TaskDao taskDao;
  final SubtaskDao subtaskDao;
  final TagDao tagDao;
  final SemesterDao semesterDao;
  final CourseDao courseDao;

  static Future<DaoTestDb> open() async {
    final Database db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: kLatestSchemaVersion,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await runMigrations(db, fromVersion: 0, toVersion: version);
        },
      ),
    );
    return DaoTestDb._(db);
  }

  Future<void> close() => db.close();

  Future<int> opLogCount() async {
    final List<Map<String, Object?>> rows = await db.query('op_log');
    return rows.length;
  }

  Future<List<Map<String, Object?>>> opLogRows() =>
      db.query('op_log', orderBy: 'rowid ASC');

  /// 某一实体类型的 op-log 行，按写入顺序（用例层「写库必留痕」的断言用）。
  Future<List<Map<String, Object?>>> opLog(String entityType) => db.query(
      'op_log',
      where: 'entity_type = ?',
      whereArgs: <Object?>[entityType],
      orderBy: 'rowid ASC');
}
