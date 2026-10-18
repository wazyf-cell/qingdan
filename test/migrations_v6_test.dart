import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/default_timetable.dart';
import 'package:qingdan/sync/intent_resolver.dart' show SyncIntent, resolveFromState;

import 'dao_test_helper.dart';

/// 迁移 v6（M6-D：模板库列 + 内置模板 seed + 三步数据迁移）的验收。
///
/// 契约见 `开发文档/02-方案设计/待执行-M6D-学期课表与模板.md` §二。
/// 内置模板「不参与同步」的实现手段是**不写 op-log**（A 通道）+
/// 预注册 sync_state 基线（B 通道终态 diff 扫全表，缺基线会被判 CREATE 推上云）。
void main() {
  ensureSqfliteFfi();

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

  group('v5 → v6 升级', () {
    test('§三常量表逐字核对（测试内独立硬编码，防常量本身被改动）', () {
      // 期望值按用户原文 HH:MM 折算成分钟：与 default_timetable.dart 是两份
      // 独立来源，只有一边被改就会红（上面的 seed 断言只查「落库=常量」，
      // 查不出「常量=原文」）。
      const List<(String, String)> hhmm = <(String, String)>[
        ('08:00', '08:45'), ('08:55', '09:40'), ('10:00', '10:45'),
        ('10:55', '11:40'), ('14:00', '14:45'), ('14:55', '15:40'),
        ('16:00', '16:45'), ('16:55', '17:40'), ('19:00', '19:45'),
        ('19:55', '20:40'), ('20:50', '21:35'), ('21:45', '22:30'),
      ];
      int toMin(String s) {
        final List<String> p = s.split(':');
        return int.parse(p[0]) * 60 + int.parse(p[1]);
      }

      expect(kBuiltInTimeDetails, hasLength(12));
      for (int i = 0; i < 12; i++) {
        expect(kBuiltInTimeDetails[i].section, i + 1);
        expect(kBuiltInTimeDetails[i].start, toMin(hhmm[i].$1),
            reason: '第 ${i + 1} 节开始时刻必须等于用户原文 ${hhmm[i].$1}');
        expect(kBuiltInTimeDetails[i].end, toMin(hhmm[i].$2),
            reason: '第 ${i + 1} 节结束时刻必须等于用户原文 ${hhmm[i].$2}');
      }
      expect(kBuiltInTimetableId, 'builtin-college');
      expect(kBuiltInTimetableName, '大学默认');
    });


    test('匿名作息绑到 active 学期；内置模板 12 行逐个等于常量；不写 op-log',
        () async {
      final Directory tmp =
          await Directory.systemTemp.createTemp('qingdan_v6_bind');
      final String path = '${tmp.path}${Platform.pathSeparator}v6.db';
      Database? handle;
      try {
        await buildV5DiskDb(path);
        handle = await openDisk(path, kLatestSchemaVersion);
        final Database db = handle;

        final Map<String, Object?> t1 =
            (await db.query('timetables', where: "id = 't1'")).first;
        expect(t1['semester_id'], 's1', reason: '§2.3 第 1 步：匿名作息绑当前学期');
        expect(t1['is_template'], 0);
        expect(t1['is_builtin'], 0);

        final Map<String, Object?> builtin = (await db
                .query('timetables',
                    where: 'id = ?', whereArgs: <Object?>[kBuiltInTimetableId]))
            .first;
        expect(builtin['name'], kBuiltInTimetableName);
        expect(builtin['semester_id'], isNull);
        expect(builtin['is_template'], 1);
        expect(builtin['is_builtin'], 1);

        final List<Map<String, Object?>> rows = await builtInRows(db);
        expect(rows, hasLength(12));
        for (int i = 0; i < 12; i++) {
          final ({int section, int start, int end}) c =
              kBuiltInTimeDetails[i];
          expect(rows[i]['section'], c.section, reason: '第 ${i + 1} 行节次');
          expect(rows[i]['start_minutes'], c.start, reason: '第 ${i + 1} 行开始');
          expect(rows[i]['end_minutes'], c.end, reason: '第 ${i + 1} 行结束');
          expect(rows[i]['id'], builtInDetailId(c.section),
              reason: '固定 id（两台设备 seed 必须同键）');
        }

        final List<Map<String, Object?>> opLog = await db.query('op_log');
        expect(
            opLog
                .where((Map<String, Object?> r) =>
                    (r['entity_id']! as String).startsWith('builtin'))
                .length,
            0,
            reason: '内置模板绝不写 op-log（A 通道靠它挡推送）');
        expect(opLog, isEmpty, reason: '迁移期间一条流水都不许产生');

        // 存量 12 行原样保留（绑学期，不被动过）。
        expect(
          await db.query('time_details',
              where: 'timetable_id = ?', whereArgs: <Object?>['t1']),
          hasLength(12),
        );
      } finally {
        await handle?.close();
        await tmp.delete(recursive: true);
      }
    });

    test('新列就位：color_index 全 NULL、import_batches.semester_id 可空存在',
        () async {
      final Directory tmp =
          await Directory.systemTemp.createTemp('qingdan_v6_cols');
      final String path = '${tmp.path}${Platform.pathSeparator}v6.db';
      Database? handle;
      try {
        await buildV5DiskDb(path);
        handle = await openDisk(path, kLatestSchemaVersion);
        final Database db = handle;

        final List<Map<String, Object?>> courses = await db.query('courses');
        expect(courses, hasLength(3));
        expect(
          courses.where((Map<String, Object?> r) => r['color_index'] != null),
          isEmpty,
          reason: '老课程 color_index 全 NULL = 沿用自动配色，不变样',
        );
        for (final String table in <String>['timetables', 'courses', 'import_batches']) {
          final Set<String> cols = (await db.rawQuery('PRAGMA table_info($table)'))
              .map((Map<String, Object?> c) => c['name']! as String)
              .toSet();
          expect(
            cols,
            containsAll(<String>[
              if (table == 'timetables') ...['is_template', 'is_builtin'],
              if (table == 'courses') 'color_index',
              if (table == 'import_batches') 'semester_id',
            ]),
            reason: '$table 缺 v6 列',
          );
        }
      } finally {
        await handle?.close();
        await tmp.delete(recursive: true);
      }
    });

    test('没有 active 学期：匿名作息标成模板；空表（无节次）删行', () async {
      // 形状 a：有节次 → is_template=1 保留。
      final Directory tmpA =
          await Directory.systemTemp.createTemp('qingdan_v6_tpl');
      final String pathA = '${tmpA.path}${Platform.pathSeparator}v6.db';
      // 形状 b：无节次 → 整行删除（空行没意义）。
      final Directory tmpB =
          await Directory.systemTemp.createTemp('qingdan_v6_del');
      final String pathB = '${tmpB.path}${Platform.pathSeparator}v6.db';
      Database? handle;
      try {
        await buildV5DiskDb(pathA, withActiveSemester: false);
        handle = await openDisk(pathA, kLatestSchemaVersion);
        final Map<String, Object?> t1 =
            (await handle.query('timetables', where: "id = 't1'")).first;
        expect(t1['is_template'], 1);
        expect(t1['semester_id'], isNull);
        await handle.close();
        handle = null;

        await buildV5DiskDb(pathB,
            withActiveSemester: false, withDetails: false);
        handle = await openDisk(pathB, kLatestSchemaVersion);
        expect(await handle.query('timetables', where: "id = 't1'"), isEmpty,
            reason: '§2.3 第 1 步：匿名且无任何节次的空作息行要删掉');
        expect(await handle.query('timetables',
            where: 'id = ?', whereArgs: <Object?>[kBuiltInTimetableId]),
            hasLength(1), reason: '内置模板不受删除影响');
        await handle.close();
        handle = null;
      } finally {
        await handle?.close();
        await tmpA.delete(recursive: true);
        await tmpB.delete(recursive: true);
      }
    });

    test('is_active 兜底：全 0 时把 created_time 最新那行置 1', () async {
      final Directory tmp =
          await Directory.systemTemp.createTemp('qingdan_v6_active');
      final String path = '${tmp.path}${Platform.pathSeparator}v6.db';
      Database? handle;
      try {
        final Database v5 = await openDisk(path, 5);
        handle = v5;
        await insertSemester(v5, id: 'old', isActive: 0, createdTime: 100);
        await insertSemester(v5, id: 'new', isActive: 0, createdTime: 900);
        await v5.close();
        handle = null;

        handle = await openDisk(path, kLatestSchemaVersion);
        final Map<String, Object?> actives = (await handle
                .query('semesters', where: 'is_active = 1'))
            .single;
        expect(actives['id'], 'new', reason: '§2.3 第 3 步：created_time 最新者兜底为当前学期');
        await handle.close();
        handle = null;
      } finally {
        await handle?.close();
        await tmp.delete(recursive: true);
      }
    });
  });

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

  test('★ v4 直接跳 v6：v5+v6 按序全跑，老数据不丢、不崩（§十一.4）', () async {
    final Directory tmp =
        await Directory.systemTemp.createTemp('qingdan_v4_to_v6');
    final String path = '${tmp.path}${Platform.pathSeparator}legacy_v4.db';
    Database? handle;
    try {
      final Database v4 = await openDisk(path, 4);
      handle = v4;
      expect(
        (await v4.rawQuery('PRAGMA table_info(time_details)'))
            .map((Map<String, Object?> r) => r['name']),
        isNot(contains('modified_time')),
        reason: '前置守卫：这一步必须真的停在 v4，否则整条测试恒真',
      );
      await insertSemester(v4);
      await insertTimetable(v4, semesterId: 's1');
      await insertDetails(v4, 't1');
      await insertCourse(v4, 'c1');
      await v4.close();
      handle = null;

      handle = await openDisk(path, kLatestSchemaVersion);
      final Database db = handle;
      final Map<String, Object?> meta = (await db.query('_meta',
              where: "key = 'applied_migration'", limit: 1))
          .first;
      expect(meta['value'], '$kLatestSchemaVersion',
          reason: '跳级升级必须把 v5、v6 按序全跑掉');

      final List<Map<String, Object?>> kept = await db.query('time_details',
          where: 'timetable_id = ?', whereArgs: <Object?>['t1'],
          orderBy: 'section ASC');
      expect(kept, hasLength(12), reason: 'v5 的 ALTER 不得动掉 v4 存量行');
      expect(kept.first['start_minutes'], 480);
      expect(
        kept.where((Map<String, Object?> r) => r['modified_time'] == null).length,
        12,
        reason: '老行补的是 NULL，不是 0',
      );
      expect(await builtInRows(db), hasLength(12),
          reason: 'v6 的 seed 在跳级路径上同样执行');
      expect(
        await db.query('op_log', where: "entity_id LIKE 'builtin%'"), isEmpty);
      expect((await db.query('semesters', where: 'is_active = 1')).single['id'],
          's1');
      await db.close();
      handle = null;
    } finally {
      await handle?.close();
      await tmp.delete(recursive: true);
    }
  });
}
