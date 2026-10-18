import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/data/device_id.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/data/sync_state_dao.dart';
import 'package:qingdan/domain/ids.dart';

import 'dao_test_helper.dart';

void main() {
  setUpAll(ensureSqfliteFfi);

  group('SyncStateDao', () {
    late DaoTestDb env;
    late SyncStateDao dao;

    setUp(() async {
      env = await DaoTestDb.open();
      dao = SyncStateDao(env.db);
    });

    tearDown(() => env.close());

    test('upsertBase + find 往返一致', () async {
      await dao.upsertBase(
        entityType: 'task',
        entityId: 't1',
        baseJson: '{"id":"t1","title":"任务A"}',
        baseEtag: 'abc123',
        deviceId: 'dev-1',
      );
      final SyncStateRow? row = await dao.find('task', 't1');
      expect(row, isNotNull);
      expect(row!.entityType, 'task');
      expect(row.entityId, 't1');
      expect(row.baseJson, '{"id":"t1","title":"任务A"}');
      expect(row.baseEtag, 'abc123');
      expect(row.deviceId, 'dev-1');
      expect(row.rev, 1);
      expect(row.syncedAt, greaterThan(0));
    });

    test('upsertBase 同实体二次落基线：rev 自增，不产生重复行', () async {
      await dao.upsertBase(
          entityType: 'task', entityId: 't1', baseJson: 'v1', deviceId: 'dev');
      await dao.upsertBase(
          entityType: 'task', entityId: 't1', baseJson: 'v2', deviceId: 'dev');
      final SyncStateRow? row = await dao.find('task', 't1');
      expect(row!.baseJson, 'v2');
      expect(row.rev, 2, reason: 'rev 每设备单调递增，是并发检测依据');
      final Map<String, SyncStateRow> all = await dao.findAllFor('task');
      expect(all, hasLength(1), reason: '复合主键 upsert，不得出现两行');
    });

    test('nextRev：无行从 1 起，有行在其上递增', () async {
      expect(await dao.nextRev('task', 'x'), 1);
      await dao.upsertBase(
          entityType: 'task', entityId: 'x', baseJson: '{}', deviceId: 'd');
      expect(await dao.nextRev('task', 'x'), 2);
    });

    test('base_json 能显式清空为 null（copyWith no-op 缺陷的绕过验证）', () async {
      await dao.upsertBase(
        entityType: 'task',
        entityId: 't1',
        baseJson: '{"id":"t1"}',
        deviceId: 'dev',
      );
      expect((await dao.find('task', 't1'))!.baseJson, isNotNull);

      // 关键断言：清空后读回来必须是 null。
      await dao.clearBase('task', 't1');
      final SyncStateRow? row = await dao.find('task', 't1');
      expect(row, isNotNull, reason: '清的是快照，行本身保留');
      expect(row!.baseJson, isNull, reason: 'SQL 层面写 null 就是 null');
      expect(row.rev, 1, reason: '清快照不归零 rev，否则并发检测退化');
    });

    test('findAllFor 按类型批量读，且不串类型', () async {
      await dao.upsertBase(
          entityType: 'task', entityId: 't1', baseJson: '{}', deviceId: 'd');
      await dao.upsertBase(
          entityType: 'list', entityId: 'l1', baseJson: '{}', deviceId: 'd');
      final Map<String, SyncStateRow> tasks = await dao.findAllFor('task');
      expect(tasks.keys, <String>['t1']);
      expect((await dao.findAllFor('tag')), isEmpty);
    });

    test('upsertBaseIn 在显式事务内可复用（同事务铁律的挂载点）', () async {
      await env.db.transaction((Transaction txn) async {
        await dao.upsertBaseIn(txn,
            entityType: 'task', entityId: 't9', baseJson: '{}', deviceId: 'd');
        // 落基线 + 标 op-log uploaded 将来同事务完成，这里验证 executor 版本可用。
      });
      expect(await dao.find('task', 't9'), isNotNull);
    });
  });

  group('DeviceId', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(
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
    });

    tearDown(() => db.close());

    test('连续两次调用返回相同值，且持久化在 _meta（非 IdGenerator 现算）', () async {
      final String first = await DeviceId.ensureDeviceId(db);
      final String second = await DeviceId.ensureDeviceId(db);
      expect(first, second, reason: 'device_id 必须一次生成、跨调用稳定');
      expect(first, isNot(IdGenerator.next()), reason: '与 IdGenerator 现算值无关');
      final List<Map<String, Object?>> rows = await db.query('_meta',
          where: "key = 'device_id'");
      expect(rows, hasLength(1));
      expect(rows.first['value'], first);
    });

    test('幂等：重复调用不产生第二行 _meta 记录', () async {
      await DeviceId.ensureDeviceId(db);
      await DeviceId.ensureDeviceId(db);
      expect(await db.query('_meta', where: "key = 'device_id'"), hasLength(1));
    });
  });
}
