// 迁移 v6 **幂等重跑 + 内置模板不进同步**的验收（自 migrations_v6_test.dart 拆出）。
//
// 内置模板「不参与同步」的实现手段是**不写 op-log**（A 通道）+
// 预注册 sync_state 基线（B 通道终态 diff 扫全表，缺基线会被判 CREATE 推上云）。
// 契约见 `开发文档/02-方案设计/待执行-M6D-学期课表与模板.md` §二。
// 升级路径的验收在孪生文件 `migrations_v6_upgrade_test.dart`。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/default_timetable.dart';
import 'package:qingdan/sync/intent_resolver.dart' show SyncIntent, resolveFromState;

import 'dao_test_helper.dart';
import 'migrations_v6_helper.dart';

void main() {
  ensureSqfliteFfi();

  group('幂等', () {
    test('v6 重跑（runMigrations 5→6 两次）：模板仍只有 1 张 12 行，不崩',
        () async {
      final Directory tmp =
          await Directory.systemTemp.createTemp('qingdan_v6_twice');
      final String path = '${tmp.path}${Platform.pathSeparator}v6.db';
      Database? handle;
      try {
        await buildV5DiskDb(path);
        handle = await openDisk(path, kLatestSchemaVersion);
        await runMigrations(handle, fromVersion: 5, toVersion: 6);
        await runMigrations(handle, fromVersion: 5, toVersion: 6);

        expect(
            await handle.query('timetables',
                where: 'id = ?', whereArgs: <Object?>[kBuiltInTimetableId]),
            hasLength(1));
        expect(await builtInRows(handle), hasLength(12));
        expect(await handle.query('op_log'), isEmpty,
            reason: '重跑也不得产生 op-log');
        final Map<String, Object?> t1 =
            (await handle.query('timetables', where: "id = 't1'")).first;
        expect(t1['semester_id'], 's1', reason: '重跑不得把已绑学期的作息改回去');
        expect(t1['is_template'], 0);
        await handle.close();
        handle = null;
      } finally {
        await handle?.close();
        await tmp.delete(recursive: true);
      }
    });

    test('空库（无任何学期/作息/课程）从 0 连跑到最新：内置模板在、不崩',
        () async {
      final Database db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: kLatestSchemaVersion,
          onConfigure: (Database d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (Database d, int v) =>
              runMigrations(d, fromVersion: 0, toVersion: v),
        ),
      );
      expect(
          await db.query('timetables',
              where: 'id = ?', whereArgs: <Object?>[kBuiltInTimetableId]),
          hasLength(1));
      expect(await builtInRows(db), hasLength(12));
      expect(await db.query('op_log'), isEmpty);
      await db.close();
    });
  });

  test('内置模板不产生同步意图（B 通道终态 diff 的封堵验证）', () async {
    final Database db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: kLatestSchemaVersion,
        onConfigure: (Database d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database d, int v) =>
            runMigrations(d, fromVersion: 0, toVersion: v),
      ),
    );
    for (final MapEntry<String, String> e in <String, String>{
          'timetable': 'timetables',
          'time_detail': 'time_details',
        }.entries) {
      final Map<String, Map<String, Object?>> current =
          <String, Map<String, Object?>>{};
      final Map<String, String?> base = <String, String?>{};
      for (final Map<String, Object?> row in await db.query(e.value)) {
        final String id = row['id']! as String;
        if (!id.startsWith(kBuiltInTimetableId)) continue;
        current[id] = row;
        final List<Map<String, Object?>> s = await db.query('sync_state',
            where: 'entity_type = ? AND entity_id = ?',
            whereArgs: <Object?>[e.key, id],
            limit: 1);
        expect(s, hasLength(1), reason: '${e.key} $id 缺 sync_state 基线');
        base[id] = s.first['base_json'] as String?;
      }
      expect(current, isNotEmpty, reason: '${e.key} 没找到内置行');
      final List<SyncIntent> intents = resolveFromState(
          entityType: e.key, currentRows: current, baseJsonByEntityId: base);
      expect(intents, isEmpty,
          reason: '${e.key}：内置模板行被 B 通道判成变更，会被推上云');
    }
    await db.close();
  });
}
