import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

// 迁移 v4：课表域五张表（F28 / F29 / F30 / F31）。
//
// 单独成文件的原因：`migrations.dart` 已接近 300 行硬红线，DDL 放原地必破。
// 表结构以 `开发文档/02-方案设计/方案设计-课表域.md` §1.1 为准；表名与列名
// 由实现方定案（见 `待执行-M4a课表导入.md` 定案 6）。
//
// **不建 `last_synced_json` 列**：同步基线自 v3 起集中在 `sync_state` 表。
// **不建 `color_index` 列**：配色由课名派生（`Course.colorIndex`），
// 落库反而会与改名后的课名不一致。

/// 学期表。
///
/// `first_week_monday` 存「该日 00:00 的 UTC 毫秒」，即按纯日期处理，
/// 周次算术只用整日差，不受设备时区影响。
const String kCreateSemesters = '''
    CREATE TABLE semesters (
      id                TEXT PRIMARY KEY,
      name              TEXT NOT NULL,
      first_week_monday INTEGER NOT NULL,
      total_weeks       INTEGER NOT NULL DEFAULT 16
                        CHECK (total_weeks BETWEEN 1 AND 30),
      is_active         INTEGER NOT NULL DEFAULT 1,
      created_time      INTEGER,
      modified_time     INTEGER
    )
  ''';

/// 作息时间表（当前版本恒为「默认作息」，`semester_id` 可空）。
const String kCreateTimetables = '''
    CREATE TABLE timetables (
      id            TEXT PRIMARY KEY,
      name          TEXT NOT NULL,
      semester_id   TEXT REFERENCES semesters(id) ON DELETE SET NULL,
      created_time  INTEGER,
      modified_time INTEGER
    )
  ''';

/// 作息明细：`第 N 节 → 当日分钟数区间`。节次允许跳号，但同一张表内唯一。
const String kCreateTimeDetails = '''
    CREATE TABLE time_details (
      id            TEXT PRIMARY KEY,
      timetable_id  TEXT NOT NULL REFERENCES timetables(id) ON DELETE CASCADE,
      section       INTEGER NOT NULL CHECK (section >= 1),
      start_minutes INTEGER NOT NULL,
      end_minutes   INTEGER NOT NULL,
      CHECK (end_minutes > start_minutes),
      UNIQUE (timetable_id, section)
    )
  ''';

/// 导入批次（本地簿记，**不参与同步**，见 2026-10-10 定案 3）。
const String kCreateImportBatches = '''
    CREATE TABLE import_batches (
      id             TEXT PRIMARY KEY,
      file_name      TEXT NOT NULL,
      imported_at    INTEGER NOT NULL,
      count_imported INTEGER NOT NULL DEFAULT 0,
      count_updated  INTEGER NOT NULL DEFAULT 0,
      count_skipped  INTEGER NOT NULL DEFAULT 0
    )
  ''';

/// 课程表。
///
/// - `weekday` 1~7（ISO，1 == 周一）；`start_section <= end_section`
///   —— 起始节大于结束节是**行错误**，导入层报错不交换（§3.3.3）；
/// - `weeks` 是排序去重后的 JSON 数组字符串，唯一真源（§2.4）；
/// - `uid` 是去重键，跨导入与同步都靠它（§3.5），故建索引；
/// - `deleted` 软删除，供「覆盖导入」识别旧数据。
const String kCreateCourses = '''
    CREATE TABLE courses (
      id              TEXT PRIMARY KEY,
      uid             TEXT NOT NULL,
      name            TEXT NOT NULL,
      teacher         TEXT,
      location        TEXT,
      weekday         INTEGER NOT NULL CHECK (weekday BETWEEN 1 AND 7),
      start_section   INTEGER NOT NULL CHECK (start_section >= 1),
      end_section     INTEGER NOT NULL,
      weeks           TEXT NOT NULL,
      raw_weeks_text  TEXT,
      semester_id     TEXT REFERENCES semesters(id) ON DELETE SET NULL,
      origin          TEXT NOT NULL DEFAULT 'manual'
                      CHECK (origin IN ('manual', 'import')),
      import_batch_id TEXT REFERENCES import_batches(id) ON DELETE SET NULL,
      deleted         INTEGER NOT NULL DEFAULT 0,
      created_time    INTEGER,
      modified_time   INTEGER,
      CHECK (end_section >= start_section)
    )
  ''';

/// 建 v4 全部表与索引。由 `migrations.dart` 的 `Migration(version: 4)` 调用。
///
/// 顺序即外键依赖顺序：`semesters` → `timetables` → `time_details` →
/// `import_batches` → `courses`。
Future<void> createCourseTables(DatabaseExecutor db) async {
  await db.execute(kCreateSemesters);
  await db.execute(kCreateTimetables);
  await db.execute(kCreateTimeDetails);
  await db.execute(kCreateImportBatches);
  await db.execute(kCreateCourses);

  // 周视图按「学期 + 星期 + 未删除」捞课；UID 去重与同步按 uid 精确查。
  await db.execute(
      'CREATE INDEX idx_courses_slot '
      'ON courses(semester_id, weekday, deleted)');
  await db.execute('CREATE INDEX idx_courses_uid ON courses(uid)');
  await db.execute(
      'CREATE INDEX idx_time_details_table '
      'ON time_details(timetable_id, section)');
}

/// 迁移 v5：给 `time_details` 补两列时间戳。
///
/// 为什么必须有：字段级 LWW 比较的是**行上的** `modified_time`。缺列时
/// `_remoteNewer` 恒为 false → 恒判本地胜 → 同一节被两端各改一次时，**胜者
/// 由谁后推送决定，而不是谁编辑得晚**（两端照样收敛，只是可能收敛到那条更早
/// 的编辑，新值被静默覆盖）。判别用例见
/// `test/sync_two_device_course_test.dart` 的「编辑时间新的那份赢」。
/// 迁移只增不改，所以 v4 的建表 DDL 原样保留，新库靠这条 ALTER 补齐。
Future<void> addTimeDetailTimestamps(DatabaseExecutor db) async {
  await db.execute(
      'ALTER TABLE time_details ADD COLUMN created_time INTEGER');
  await db.execute(
      'ALTER TABLE time_details ADD COLUMN modified_time INTEGER');
}
