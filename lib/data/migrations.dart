import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'course_tables.dart';
import 'migration_v1_v3.dart';
import 'migration_v5.dart';
import 'migration_v6.dart';

/// 单条版本化迁移：从上一版本升到 [version] 时执行 [up]。
///
/// 约定：
/// - 版本号从 1 开始，连续递增，不跳号、不改历史条目；
/// - [up] 内只做 DDL / 数据搬运，不做任何业务判断；
/// - M1 仅建 `_meta` 表，业务表由后续里程碑按需追加。
/// [db] 是迁移执行目标：sqflite 传入 `Database`（实现 `DatabaseExecutor`），
/// 每条迁移由 runMigrations 包在独立事务里执行。
typedef MigrationFn = Future<void> Function(DatabaseExecutor db);

class Migration {
  const Migration({
    required this.version,
    required this.description,
    required this.up,
  });

  /// 迁移到达的目标 schema 版本。
  final int version;

  /// 一句话说明本次迁移建/改了什么，用于日志与排查。
  final String description;

  final MigrationFn up;
}

/// 全部迁移，按 version 升序排列。最新版本取最后一项的 version。
///
/// M6-D §2.1 拆文件：本文件只留「注册表 + 执行器」；v1–v3 的 DDL 在
/// `migration_v1_v3.dart`，v4 在 `course_tables.dart`，v5 在
/// `migration_v5.dart`，v6 在 `migration_v6.dart`。历史条目内容一字未改。
final List<Migration> kMigrations = <Migration>[
  Migration(
    version: 1,
    description: '创建 _meta 元数据表（schema 版本等键值对）',
    up: createMetaTable,
  ),
  Migration(
    version: 2,
    description: '创建业务表：清单/任务/子任务/标签/任务标签关联 + op-log，'
        '清理 v1 遗留的 created_at 占位行',
    up: createBusinessTables,
  ),
  Migration(
    version: 3,
    description: '新增集中式同步基线表 sync_state（M2，取代实体表的 '
        'last_synced_json 列），补 op_log 实体分组索引，并把存量 '
        'last_synced_json 搬运一次',
    up: createSyncState,
  ),
  Migration(
    version: 4,
    description: '课表域五张表：semesters / timetables / time_details / '
        'courses / import_batches（M4a，DDL 与外键顺序见 course_tables.dart）',
    up: createCourseTables,
  ),
  Migration(
      version: 5,
      description: 'time_details 补 created_time/modified_time：缺列级时间戳时字段级 '
          'LWW 恒判本地胜，同一节被两端各改一次会按推送顺序而非编辑时间定胜者',
      up: addTimeDetailTimestamps),
  Migration(
      version: 6,
      description: 'M6-D：timetables 加 is_template/is_builtin、courses 加 color_index、'
          'import_batches 加 semester_id（全部 ADD COLUMN，不加 CHECK）；'
          '同事务三步数据迁移：匿名作息绑当前学期 → seed 内置模板 builtin-college'
          '（固定 id、INSERT OR IGNORE、不写 op-log，不参与同步）→ is_active 兜底',
      up: migrateV6),
];

/// 当前最新 schema 版本。
int get kLatestSchemaVersion => kMigrations.last.version;

/// [db] 是 sqflite 传入的连接对象；每条迁移由本函数包在独立事务里执行。
/// 公开导出以便测试在内存库上重放同一迁移序列（与应用入口完全一致）。
Future<void> runMigrations(
  Database db, {
  required int fromVersion,
  required int toVersion,
}) async {
  for (final Migration m in kMigrations) {
    if (m.version <= fromVersion || m.version > toVersion) continue;
    await db.transaction((Transaction txn) async {
      await m.up(txn);
      // upsert：v1 迁移已写入 key='applied_migration'（value=1），
      // 后续版本记录同一 key 以 replace 更新到最新已应用版本号。
      await txn.insert(
        '_meta',
        {'key': 'applied_migration', 'value': '${m.version}'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}
