// 迁移 v6（M6-D：模板库列 + 内置模板 seed + 三步数据迁移）**升级路径**的验收。
//
// 契约见 `开发文档/02-方案设计/待执行-M6D-学期课表与模板.md` §二。
// 共用夹具（磁盘库 + 插行辅助）在 `migrations_v6_helper.dart`；
// 幂等重跑与「内置模板不进同步」的封堵验证在孪生文件
// `migrations_v6_seed_idempotency_test.dart`。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/default_timetable.dart';

import 'dao_test_helper.dart';
import 'migrations_v6_helper.dart';

void main() {
  ensureSqfliteFfi();

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
