import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

// 迁移 v1–v3 的 DDL 与数据搬运。
//
// 本文件是从 `migrations.dart` 拆出的搬家产物（M6-D §2.1：migrations.dart
// 触 300 行红线，只留 Migration 类 / kMigrations / kLatestSchemaVersion /
// runMigrations）。**内容一字未改**（总纲铁律 4：历史条目不得修改，搬文件
// 不算改内容），仅把文件内私有函数改为公开以便 migrations.dart 引用。

/// v1：建 `_meta` 元数据表。由 `migrations.dart` 的 `Migration(version: 1)` 调用。
Future<void> createMetaTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE _meta (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
  await db.insert('_meta', {'key': 'schema_version', 'value': '1'});
  await db.insert('_meta', {'key': 'created_at', 'value': 'utc_now'});
}

/// 清单表（F6）。
///
/// 删除语义：清单本身不进回收站，采用物理删除（F4 的回收站只针对任务）。
/// 任务表对 `lists(id)` 的外键用 ON DELETE SET NULL：删清单时其任务**保留**
/// 并落回收集箱（list_id → NULL），避免孤儿任务与级联误删。
const String _kCreateListsTable = '''
    CREATE TABLE lists (
      id               TEXT PRIMARY KEY,
      name             TEXT NOT NULL,
      sort_order       INTEGER NOT NULL DEFAULT 0,
      created_time     INTEGER,
      modified_time    INTEGER,
      last_synced_json TEXT
    )
  ''';

/// 任务表（F2/F3/F4）。
///
/// 回收站语义：`deleted` 0/1 + `deleted_time`；普通查询过滤
/// `deleted = 0`，回收站查询反之；彻底删除才物理 DELETE。
const String _kCreateTasksTable = '''
    CREATE TABLE tasks (
      id               TEXT PRIMARY KEY,
      title            TEXT NOT NULL,
      note             TEXT NOT NULL DEFAULT '',
      priority         INTEGER NOT NULL DEFAULT 0,
      start_date       INTEGER,
      end_date         INTEGER,
      due_date         INTEGER,
      list_id          TEXT REFERENCES lists(id) ON DELETE SET NULL,
      completed        INTEGER NOT NULL DEFAULT 0,
      completed_time   INTEGER,
      created_time     INTEGER,
      modified_time    INTEGER,
      sort_order       INTEGER NOT NULL DEFAULT 0,
      deleted          INTEGER NOT NULL DEFAULT 0,
      deleted_time     INTEGER,
      last_synced_json TEXT
    )
  ''';

/// 子任务表（F5，单层）。父任务彻底删除时子任务随之物理删除（CASCADE）。
const String _kCreateSubtasksTable = '''
    CREATE TABLE subtasks (
      id               TEXT PRIMARY KEY,
      task_id          TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
      title            TEXT NOT NULL,
      completed        INTEGER NOT NULL DEFAULT 0,
      sort_order       INTEGER NOT NULL DEFAULT 0,
      modified_time    INTEGER,
      last_synced_json TEXT
    )
  ''';

/// 标签表（F11，P1）。M1 只建表，不提供用例与 UI。
const String _kCreateTagsTable = '''
    CREATE TABLE tags (
      id               TEXT PRIMARY KEY,
      name             TEXT NOT NULL,
      color            TEXT,
      modified_time    INTEGER,
      last_synced_json TEXT
    )
  ''';

/// 任务↔标签关联（F11）。复合主键；任务/标签任一方物理删除时级联清关联。
const String _kCreateTaskTagsTable = '''
    CREATE TABLE task_tags (
      task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
      tag_id  TEXT NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
      PRIMARY KEY (task_id, tag_id)
    )
  ''';

/// op-log（F38）：本地所有写操作的审计流水。
///
/// - M1 只写不读，`uploaded` 恒为 0（M2 上传成功后置位）；
/// - M1 **不建**意图表：上传以「同步时扫描 op-log 中未上传记录、按
///   (entity_type, entity_id) 收敛到终态」的方式实现（详见变更日志）；
///   M2 若证实需要独立意图表，新迁移建表 + 对 op_log 追加消费标记即可，
///   M1 的写入路径无需任何改动；
/// - `entity_id` 不设外键：任务彻底删除后其 op-log 流水必须留存（审计）。
const String _kCreateOpLogTable = '''
    CREATE TABLE op_log (
      id            TEXT PRIMARY KEY,
      entity_type   TEXT NOT NULL,
      entity_id     TEXT NOT NULL,
      operation     TEXT NOT NULL,
      changes_json  TEXT NOT NULL,
      operated_time INTEGER NOT NULL,
      uploaded      INTEGER NOT NULL DEFAULT 0,
      uploaded_time INTEGER
    )
  ''';

/// v2：建业务表 + 索引，清 v1 占位行。
Future<void> createBusinessTables(DatabaseExecutor db) async {
  await db.execute(_kCreateListsTable);
  await db.execute(_kCreateTasksTable);
  await db.execute(_kCreateSubtasksTable);
  await db.execute(_kCreateTagsTable);
  await db.execute(_kCreateTaskTagsTable);
  await db.execute(_kCreateOpLogTable);

  // modified_time 索引：各表字段级 LWW 扫描与排序的公共路径。
  await db.execute(
      'CREATE INDEX idx_lists_modified  ON lists(modified_time)');
  await db.execute(
      'CREATE INDEX idx_tasks_modified  ON tasks(modified_time)');
  await db.execute(
      'CREATE INDEX idx_subtasks_modified ON subtasks(modified_time)');
  await db.execute(
      'CREATE INDEX idx_tags_modified   ON tags(modified_time)');

  // 常用查询路径索引。
  // F6：侧栏清单按 sort_order 排序。
  await db.execute(
      'CREATE INDEX idx_lists_sort ON lists(sort_order)');
  // F8/F9：按清单 + 未完成 + 手动排序（最高频列表查询）。
  await db.execute('CREATE INDEX idx_tasks_list_active_sort '
      'ON tasks(list_id, sort_order) WHERE deleted = 0 AND completed = 0');
  // F8：智能清单「今天 / 最近 7 天」按到期时间取未完成任务。
  await db.execute('CREATE INDEX idx_tasks_due_active '
      'ON tasks(due_date) WHERE deleted = 0 AND completed = 0');
  // F3：已完成历史按完成时间倒序。
  await db.execute('CREATE INDEX idx_tasks_completed_time '
      'ON tasks(completed_time) WHERE completed = 1');
  // F5：父任务详情取子任务列表（父任务彻底删除时的级联扫描）。
  await db.execute(
      'CREATE INDEX idx_subtasks_task ON subtasks(task_id, sort_order)');
  // F11：按标签筛任务；按任务取标签。
  await db.execute(
      'CREATE INDEX idx_task_tags_tag ON task_tags(tag_id)');
  // F38 / M2：扫描未上传记录按时间序推送。
  await db.execute('CREATE INDEX idx_op_log_unuploaded '
      'ON op_log(operated_time) WHERE uploaded = 0');
  // F10：标题搜索。
  await db.execute(
      'CREATE INDEX idx_tasks_title ON tasks(title)');

  // 清理 v1 的占位行：'utc_now' 是字面量而非时间戳，无意义（保留 schema_version）。
  await db
      .delete('_meta', where: "key = 'created_at' AND value = 'utc_now'");
}

/// 同步基线表（M2，v3 迁移）。设计见《方案设计.md》§5.1。
///
/// 为什么集中一张表而不是给实体表各加列：
/// 1. `task_tags` 复合主键且没有 `last_synced_json` 列，标签关联无处放 base；
/// 2. 实体模型的 `copyWith(lastSyncedJson: null)` 是 no-op，base 若留在实体里
///    清不掉；移到独立表后由 SQL 层面直接写 NULL，缺陷自动绕过；
/// 3. 生命周期不同：实体物理删除后 `sync_state` 行要留到 tombstone 上传成功，
///    故 `entity_id` 不设外键；
/// 4. 避免 `rev` 的读-改-写散在 4 个 DAO 里。
const String _kCreateSyncStateTable = '''
    CREATE TABLE sync_state (
      entity_type TEXT NOT NULL,
      entity_id   TEXT NOT NULL,
      base_json   TEXT,
      base_etag   TEXT,
      rev         INTEGER NOT NULL DEFAULT 0,
      device_id   TEXT,
      synced_at   INTEGER NOT NULL,
      PRIMARY KEY (entity_type, entity_id)
    )
  ''';

/// 搬运一张实体表的存量 `last_synced_json` 到 `sync_state`。
///
/// M1 期间该列恒为 null 从未被写（方案设计 §5.1），实际搬不到行；但迁移
/// 必须写对：万一某设备升到过「写了 last_synced_json」的中间版本，升级后
/// 基线不能凭空丢失。`synced_at` 取迁移时刻（无更精确的历史时间可考）。
/// `entity_type` 用同步域的单数命名（'task' 等），与 op_log 的取值一致，
/// 不能直接用表名。
Future<void> _migrateLastSyncedJson(DatabaseExecutor db) async {
  final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
  const Map<String, String> tableToType = <String, String>{
    'tasks': 'task',
    'lists': 'list',
    'subtasks': 'subtask',
    'tags': 'tag',
  };
  for (final MapEntry<String, String> e in tableToType.entries) {
    await db.execute(
      "INSERT INTO sync_state(entity_type, entity_id, base_json, synced_at) "
      "SELECT '${e.value}', id, last_synced_json, $now "
      "FROM ${e.key} WHERE last_synced_json IS NOT NULL",
    );
  }
}

/// v3：建 sync_state 表 + op_log 实体分组索引 + 存量搬运。
Future<void> createSyncState(DatabaseExecutor db) async {
  await db.execute(_kCreateSyncStateTable);

  // A 通道（物理删意图）按 (entity_type, entity_id) 分组扫 op-log；
  // 现有 idx_op_log_unuploaded 只优化时间序扫描，缺此索引会退化为全表扫。
  await db.execute(
      'CREATE INDEX idx_op_log_entity '
      'ON op_log(entity_type, entity_id, operated_time)');

  await _migrateLastSyncedJson(db);
}
