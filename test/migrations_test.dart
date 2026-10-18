import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/field_change.dart';

void main() {
  // FFI 工厂是桌面端/测试端的 sqflite 入口（生产代码同样用它）。
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// 从 0 开始跑全部迁移的内存库。
  Future<Database> openFresh() async {
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
    return db;
  }

  group('迁移 0 → 最新版本', () {
    test('v1 建 _meta 且清除 created_at 占位行', () async {
      final Database db = await openFresh();
      final List<Map<String, Object?>> meta =
          await db.query('_meta', orderBy: 'key ASC');
      final Set<String> keys = meta.map((Map<String, Object?> r) => r['key']! as String).toSet();
      expect(keys, containsAll(<String>['schema_version', 'applied_migration']));
      expect(keys, isNot(contains('created_at')),
          reason: 'v2 应清除 v1 遗留的 created_at=utc_now 占位行');
      final Map<String, Object?> schemaRow = meta.firstWhere(
          (Map<String, Object?> r) => r['key'] == 'schema_version');
      expect(schemaRow['value'], '1');
      await db.close();
    });

    test('v2 建齐 6 张业务表', () async {
      final Database db = await openFresh();
      final List<Map<String, Object?>> tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name");
      final Set<String> names =
          tables.map((Map<String, Object?> r) => r['name']! as String).toSet();
      expect(
        names,
        containsAll(<String>[
          '_meta', 'lists', 'tasks', 'subtasks', 'tags', 'task_tags', 'op_log',
        ]),
      );
      await db.close();
    });

    test('v3 建 sync_state 表且列结构正确', () async {
      final Database db = await openFresh();
      final List<Map<String, Object?>> columns =
          await db.rawQuery('PRAGMA table_info(sync_state)');
      final Map<String, String?> colType = <String, String?>{
        for (final Map<String, Object?> c in columns)
          c['name']! as String: c['type'] as String?,
      };
      expect(
        colType.keys,
        containsAll(<String>[
          'entity_type', 'entity_id', 'base_json',
          'base_etag', 'rev', 'device_id', 'synced_at',
        ]),
      );
      // 可空性契约：base_json/base_etag/device_id 必须可空（清空基线 = 写 NULL）。
      expect(colType['base_json'], 'TEXT');
      expect(colType['base_etag'], 'TEXT');
      expect(colType['device_id'], 'TEXT');
      expect(colType['rev'], 'INTEGER');
      expect(colType['synced_at'], 'INTEGER');
      // 复合主键 (entity_type, entity_id)：重复键应被拒绝。
      await db.insert('sync_state', {
        'entity_type': 'task', 'entity_id': 't1',
        'base_json': '{}', 'synced_at': 1,
      });
      await expectLater(
        db.insert('sync_state', {
          'entity_type': 'task', 'entity_id': 't1',
          'base_json': '{}', 'synced_at': 2,
        }),
        throwsA(anything),
      );
      await db.close();
    });

    test('v2 关键索引存在', () async {
      final Database db = await openFresh();
      final List<Map<String, Object?>> indexes = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name IS NOT NULL");
      final Set<String> names =
          indexes.map((Map<String, Object?> r) => r['name']! as String).toSet();
      expect(
        names,
        containsAll(<String>[
          'idx_tasks_modified',
          'idx_tasks_list_active_sort',
          'idx_tasks_due_active',
          'idx_subtasks_task',
          'idx_op_log_unuploaded',
          'idx_op_log_entity',
        ]),
      );
      await db.close();
    });

    test('重复执行同区间迁移（幂等，不重复建表）', () async {
      final Database db = await openFresh();
      // 已在 v2 的库上重放 (0,2] 应报错而非静默重建——迁移只在 onCreate/onUpgrade
      // 流程内由 sqflite 控制执行，这里验证「正常打开后表结构稳定」。
      final List<Map<String, Object?>> tables = await db.rawQuery(
          "SELECT count(*) AS c FROM sqlite_master WHERE type = 'table'");
      expect(
          tables.first['c'],
          13, // _meta + 6 业务表 + sync_state（v3）+ 课表域 5 张（v4）
          reason: '表数量是硬计数：新增表必须在此登记，防止重复建表或漏建悄悄发生');
      final List<Map<String, Object?>> names = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      expect(
        names.map((Map<String, Object?> r) => r['name']).toSet(),
        containsAll(<String>[
          'semesters', 'timetables', 'time_details', 'courses', 'import_batches',
        ]),
      );
      await db.close();
    });

    test('v3 迁移不更新 _meta.schema_version（遗留死值恒为 1，真实版本在 applied_migration）', () async {
      final Database db = await openFresh();
      final List<Map<String, Object?>> meta = await db.query('_meta');
      final Map<String, String> kv = <String, String>{
        for (final Map<String, Object?> r in meta)
          r['key']! as String: r['value']! as String,
      };
      expect(kv['schema_version'], '1',
          reason: 'schema_version 是遗留死值，任何迁移都不得更新它');
      expect(kv['applied_migration'], '$kLatestSchemaVersion',
          reason: '真实迁移版本由 applied_migration 承载');
      await db.close();
    });

    test('v3 存量搬运：带 last_synced_json 的 v2 库升 v3 后基线落入 sync_state', () async {
      // 真实升级路径必须用磁盘库：内存库一关即销毁，无法「关闭后以 v2 重开再升级」。
      final Directory tmp = await Directory.systemTemp.createTemp('qingdan_mig');
      final String path =
          '${tmp.path}${Platform.pathSeparator}upgrade_v2_v3.db';
      try {
        Database db2 = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: (Database db, int version) async {
              await runMigrations(db, fromVersion: 0, toVersion: version);
            },
          ),
        );
        await db2.insert('tasks', {
          'id': 't1', 'title': '旧任务', 'last_synced_json': '{"id":"t1"}',
        });
        await db2.insert('lists', {
          'id': 'l1', 'name': '工作', 'last_synced_json': '{"id":"l1"}',
        });
        await db2.close();

        db2 = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: kLatestSchemaVersion,
            onUpgrade: (Database db, int from, int to) async {
              await runMigrations(db, fromVersion: from, toVersion: to);
            },
          ),
        );
        final List<Map<String, Object?>> rows = await db2.query('sync_state',
            orderBy: 'entity_type ASC');
        expect(rows, hasLength(2),
            reason: 'task 与 list 各搬一行，NULL 基线不搬');
        expect(rows.map((Map<String, Object?> r) => r['entity_type']),
            <String>['list', 'task']);
        expect(rows.firstWhere((Map<String, Object?> r) =>
            r['entity_type'] == 'task')['base_json'], '{"id":"t1"}');
        // rev 默认 0、base_etag/device_id 默认 NULL。
        final Map<String, Object?> taskRow = rows.firstWhere(
            (Map<String, Object?> r) => r['entity_type'] == 'task');
        expect(taskRow['rev'], 0);
        expect(taskRow['base_etag'], isNull);
        expect(taskRow['device_id'], isNull);
        await db2.close();
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  group('外键语义', () {
    test('删清单：任务保留且 list_id 置 NULL（SET NULL，落收集箱）', () async {
      final Database db = await openFresh();
      await db.insert('lists', {'id': 'l1', 'name': '工作'});
      await db.insert('tasks', {'id': 't1', 'title': '任务A', 'list_id': 'l1'});
      await db.delete('lists', where: 'id = ?', whereArgs: <Object?>['l1']);
      final List<Map<String, Object?>> rows =
          await db.query('tasks', where: 'id = ?', whereArgs: <Object?>['t1']);
      expect(rows, hasLength(1), reason: '删清单不应级联删任务');
      expect(rows.first['list_id'], isNull);
      await db.close();
    });

    test('删任务：子任务与关联标签 CASCADE，op-log 留存', () async {
      final Database db = await openFresh();
      await db.insert('tasks', {'id': 't1', 'title': '任务A'});
      await db.insert('tags', {'id': 'g1', 'name': '重要'});
      await db.insert('subtasks', {'id': 's1', 'task_id': 't1', 'title': '步骤1'});
      await db.insert('task_tags', {'task_id': 't1', 'tag_id': 'g1'});
      await db.insert('op_log', {
        'id': 'op0', 'entity_type': 'task', 'entity_id': 't1',
        'operation': 'create', 'changes_json': '[]', 'operated_time': 1,
      });
      await db.delete('tasks', where: 'id = ?', whereArgs: <Object?>['t1']);
      expect(await db.query('subtasks'), isEmpty, reason: '子任务应级联删除');
      expect(await db.query('task_tags'), isEmpty, reason: '关联应级联删除');
      expect(await db.query('tags'), isNotEmpty, reason: '标签本体不受级联影响');
      expect(await db.query('op_log'), hasLength(1),
          reason: '彻底删除后流水必须留存（审计），故 entity_id 无外键');
      await db.close();
    });

    test('外键开启时插入孤儿子任务应失败', () async {
      final Database db = await openFresh();
      await expectLater(
        db.insert('subtasks', {'id': 's1', 'task_id': 'nope', 'title': 'x'}),
        throwsA(anything),
      );
      await db.close();
    });
  });

  group('FieldChange 序列化', () {
    test('encodeChanges / decodeChanges 往返一致', () {
      const List<FieldChange> changes = <FieldChange>[
        FieldChange(field: 'title', oldValue: 'a', newValue: 'b'),
        FieldChange(field: 'completed', oldValue: 0, newValue: 1),
      ];
      final String json = encodeChanges(changes);
      final List<FieldChange> back = decodeChanges(json);
      expect(back, hasLength(2));
      expect(back.first.field, 'title');
      expect(back.first.oldValue, 'a');
      expect(back.first.newValue, 'b');
      expect(back.last.field, 'completed');
      expect(back.last.newValue, 1);
    });

    test('encodeChanges 产生 JSON 对象数组（F38 验收格式）', () {
      final String json = encodeChanges(<FieldChange>[
        const FieldChange(field: 'title', oldValue: null, newValue: '新'),
      ]);
      expect(json, '[{"field":"title","old":null,"new":"新"}]');
    });
  });
}
