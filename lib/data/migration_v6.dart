import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../domain/default_timetable.dart';
import '../domain/time_table.dart';

/// 迁移 v6（M6-D §二）：模板库两列 + 课程颜色列 + 批次学期列，
/// 随后三步数据迁移（绑作息 / seed 内置模板 / is_active 兜底）。
///
/// 幂等性：`kMigrations` 在「新库 onCreate 从 0 连跑」与「旧库 onUpgrade」
/// 两条路径上都要能安全重跑——
/// - ALTER 前先查 `PRAGMA table_info`（SQLite 无 IF NOT EXISTS，重复 ALTER
///   会直接报 duplicate column，重跑迁移就崩）；
/// - seed 一律 `INSERT OR IGNORE`（固定 id，见 §2.3 第 2 步）；
/// - 三步 UPDATE/DELETE 的条件各自排除已处理行与内置行，重跑为 no-op。
///
/// 整条迁移由 `runMigrations` 包在一个事务里执行（§2.3「写在一个事务里」）。
/// **绝不写 op-log**：内置模板「不参与同步」的实现手段。
Future<void> migrateV6(DatabaseExecutor db) async {
  // ---- §2.2 DDL：全部 ALTER TABLE ADD COLUMN，不加 CHECK ----
  await _addColumnIfMissing(db, 'timetables', 'is_template',
      'INTEGER NOT NULL DEFAULT 0');
  await _addColumnIfMissing(db, 'timetables', 'is_builtin',
      'INTEGER NOT NULL DEFAULT 0');
  await _addColumnIfMissing(db, 'courses', 'color_index',
      'INTEGER'); // 可空：NULL = 沿用按课程名哈希的自动配色
  await _addColumnIfMissing(db, 'import_batches', 'semester_id',
      'TEXT'); // 可空：老批次留 NULL（历史面板显示「（学期未知）」，§八）

  await _bindLegacyTimetable(db);
  await _seedBuiltInTemplate(db);
  await _ensureActiveSemester(db);
}

/// §2.3 第 1 步：把老库那张匿名作息（`semester_id IS NULL` 且非模板）
/// 绑到当前学期；没有当前学期时标成模板，空表（无任何节次）则删行。
/// `is_builtin = 1` 的行永远不进本步（内置模板由第 2 步 seed，且它本就是模板）。
Future<void> _bindLegacyTimetable(DatabaseExecutor db) async {
  final List<Map<String, Object?>> active = await db.query(
    'semesters',
    where: 'is_active = 1',
    limit: 1,
  );
  if (active.isNotEmpty) {
    await db.execute(
      'UPDATE timetables SET semester_id = ?, is_template = 0 '
      'WHERE semester_id IS NULL AND is_template = 0',
      <Object?>[active.first['id']],
    );
  } else {
    await db.execute(
      'UPDATE timetables SET is_template = 1 '
      'WHERE semester_id IS NULL AND is_template = 0',
    );
    await db.execute(
      'DELETE FROM timetables '
      'WHERE semester_id IS NULL AND is_template = 1 AND is_builtin = 0 '
      'AND NOT EXISTS (SELECT 1 FROM time_details td '
      'WHERE td.timetable_id = timetables.id)',
    );
  }
}

/// §2.3 第 2 步：seed 内置默认模板（`builtin-college` + 12 行固定 id 节次）。
///
/// **不写 op-log**。另需把 seed 行预注册进 `sync_state` 基线：同步引擎的
/// B 通道（`resolveFromState`）对 `timetables` / `time_details` 全表扫终态
/// diff，缺基线的行会被判成 CREATE 推上云——「不写 op-log」只挡住了 A 通道
/// （物理删）。把与 seed 行完全一致的 base_json 先落进 sync_state，diff
/// 恒为空，内置模板才真正「不参与同步」。INSERT OR IGNORE 保证重跑安全。
Future<void> _seedBuiltInTemplate(DatabaseExecutor db) async {
  final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
  // 节次内容真源 = default_timetable.dart 常量表（固定 id 'builtin-college-NN'）。
  final List<TimeDetail> details = builtInDetails(kBuiltInTimetableId);
  await db.execute(
    'INSERT OR IGNORE INTO timetables '
    '(id, name, semester_id, is_template, is_builtin, created_time, modified_time) '
    'VALUES (?, ?, NULL, 1, 1, ?, ?)',
    <Object?>[kBuiltInTimetableId, kBuiltInTimetableName, now, now],
  );
  for (final TimeDetail d in details) {
    await db.execute(
      'INSERT OR IGNORE INTO time_details '
      '(id, timetable_id, section, start_minutes, end_minutes, created_time, modified_time) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        d.id, kBuiltInTimetableId, d.section, d.startMinutes, d.endMinutes, now, now
      ],
    );
  }
  // 基线 JSON 的键必须与引擎 `_rowToSyncJson`（列名转 camelCase）逐列一致。
  await _ignoreSyncBaseline(
    db,
    type: 'timetable',
    id: kBuiltInTimetableId,
    now: now,
    json: <String, Object?>{
      'id': kBuiltInTimetableId,
      'name': kBuiltInTimetableName,
      'semesterId': null,
      'isTemplate': 1,
      'isBuiltin': 1,
      'createdTime': now,
      'modifiedTime': now,
    },
  );
  for (final TimeDetail d in details) {
    await _ignoreSyncBaseline(
      db,
      type: 'time_detail',
      id: d.id,
      now: now,
      json: <String, Object?>{
        'id': d.id,
        'timetableId': kBuiltInTimetableId,
        'section': d.section,
        'startMinutes': d.startMinutes,
        'endMinutes': d.endMinutes,
        'createdTime': now,
        'modifiedTime': now,
      },
    );
  }
}

Future<void> _ignoreSyncBaseline(
  DatabaseExecutor db, {
  required String type,
  required String id,
  required int now,
  required Map<String, Object?> json,
}) async {
  await db.execute(
    'INSERT OR IGNORE INTO sync_state '
    '(entity_type, entity_id, base_json, synced_at) VALUES (?, ?, ?, ?)',
    <Object?>[type, id, jsonEncode(json), now],
  );
}

/// §2.3 第 3 步：`is_active` 兜底。`is_active` 是自 D 批起的设备本地状态
/// （不再从同步来），本地必须永远有一个当前学期，否则课表页整页空白。
Future<void> _ensureActiveSemester(DatabaseExecutor db) async {
  final List<Map<String, Object?>> total =
      await db.rawQuery('SELECT COUNT(*) AS c FROM semesters');
  if ((total.first['c']! as int) == 0) return;
  final List<Map<String, Object?>> active = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM semesters WHERE is_active = 1');
  if ((active.first['c']! as int) > 0) return;
  await db.execute(
    'UPDATE semesters SET is_active = 1 WHERE id = '
    '(SELECT id FROM semesters ORDER BY created_time DESC LIMIT 1)',
  );
}

/// `ALTER TABLE ADD COLUMN`（列不存在时才执行）。SQLite 不支持
/// IF NOT EXISTS，而 v6 必须能被重复执行（幂等要求，见文件头）。
Future<void> _addColumnIfMissing(
  DatabaseExecutor db,
  String table,
  String column,
  String definition,
) async {
  final List<Map<String, Object?>> cols =
      await db.rawQuery('PRAGMA table_info($table)');
  final bool exists = cols.any((Map<String, Object?> c) => c['name'] == column);
  if (exists) return;
  await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
}
