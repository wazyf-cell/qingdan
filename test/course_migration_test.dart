import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

import 'dao_test_helper.dart';

/// 课表域迁移（v4 建表 + v5 补时间戳）的约束与外键语义测试。
///
/// 关注点：DDL 里写下的 CHECK / UNIQUE / REFERENCES **必须真的生效**——
/// 它们是导入层出错时的最后一道闸，也是 S6 同步落库顺序（父先于子）的依据。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb env;
  setUp(() async => env = await DaoTestDb.open());
  tearDown(() async => env.close());

  Future<void> expectRejected(Future<Object?> action) =>
      expectLater(action, throwsA(isA<DatabaseException>()));

  Map<String, Object?> courseRow({
    String id = 'c1',
    int weekday = 1,
    int start = 1,
    int end = 2,
    String? semesterId,
  }) =>
      Course(
        id: id,
        uid: 'u_$id',
        name: '高等数学',
        weekday: weekday,
        startSection: start,
        endSection: end,
        weeks: const <int>[1, 2],
        semesterId: semesterId,
      ).toMap();

  test('迁移全应用：applied_migration 记到最新版本，且不动 _meta.schema_version 死值',
      () async {
    final List<Map<String, Object?>> meta = await env.db.query('_meta');
    final Map<String, String> kv = <String, String>{
      for (final Map<String, Object?> r in meta)
        r['key']! as String: r['value']! as String,
    };
    expect(kv['applied_migration'], '$kLatestSchemaVersion');
    expect(kv['schema_version'], '1');
  });

  test('v5：time_details 补上了 created_time / modified_time 两列', () async {
    // 缺这两列时字段级 LWW 恒判本地胜（S6 的必修项），所以列本身要有断言。
    final List<Map<String, Object?>> cols =
        await env.db.rawQuery('PRAGMA table_info(time_details)');
    expect(cols.map((Map<String, Object?> r) => r['name']).toSet(),
        containsAll(<String>['created_time', 'modified_time']));
  });

  test('★ 老库升级：v4 已写入 12 节次（表里没有时间戳列）时，v5 的 ALTER 必须成功且存量行一条不丢', () async {
    // 为什么单独写这条：既有测试的 v5 断言跑在**刚建好的空表**上，而真机
    // （Android，`user_version=4`，12 行节次）升级时 `ALTER TABLE` 面对的是
    // 非空表。表重建式的写法（新建表 + 拷列）在空表上照样绿，在有行的库上
    // 会把存量作息清空——只有这个形状能抓到。
    final Directory tmp =
        await Directory.systemTemp.createTemp('qingdan_v4_to_v5');
    final String path =
        '${tmp.path}${Platform.pathSeparator}legacy_v4.db';
    // handle 只为「断言抛出时也能释放句柄」而存在：Windows 上库文件被占着，
    // finally 里的 delete 会抛 PathAccessException，而 **finally 抛错会吞掉
    // 原始断言错误**——本条测试第一次就红成了「删不掉临时目录」，看不出哪儿坏。
    Database? handle;
    try {
      // 1. 以 v4 建库并按 v4 的列形状写入（不能走 DAO：实体层的 toMap 现在
      //    会带 created_time/modified_time 两个键，v4 表里没这两列，直接报错）。
      final Database v4 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onConfigure: (Database d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (Database d, int v) =>
              runMigrations(d, fromVersion: 0, toVersion: v),
        ),
      );
      handle = v4;
      expect(
        (await v4.rawQuery('PRAGMA table_info(time_details)'))
            .map((Map<String, Object?> r) => r['name']),
        isNot(contains('modified_time')),
        reason: '前置守卫：这一步必须真的停在 v4，否则整条测试恒真',
      );
      await v4.insert('semesters', <String, Object?>{
        'id': 's1',
        'name': '老学期',
        'first_week_monday': DateTime.utc(2025, 9, 1).millisecondsSinceEpoch,
        'total_weeks': 20,
        'is_active': 1,
        'created_time': 1,
        'modified_time': 1,
      });
      await v4.insert('timetables', <String, Object?>{
        'id': 't1',
        'name': '默认作息',
        'semester_id': 's1',
        'created_time': 1,
        'modified_time': 1,
      });
      for (int i = 1; i <= 12; i++) {
        await v4.insert('time_details', <String, Object?>{
          'id': 'd$i',
          'timetable_id': 't1',
          'section': i,
          'start_minutes': 480 + (i - 1) * 55,
          'end_minutes': 525 + (i - 1) * 55,
        });
      }
      await v4.close();
      handle = null;

      // 2. 以最新版本重开：走真实应用的 onUpgrade 路径（只跑 (4,5] 区间）。
      final Database v5 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: kLatestSchemaVersion,
          onConfigure: (Database d) => d.execute('PRAGMA foreign_keys = ON'),
          onUpgrade: (Database d, int from, int to) =>
              runMigrations(d, fromVersion: from, toVersion: to),
        ),
      );
      handle = v5;

      // 3. 列补上了，且 12 行内容原样还在，时间戳为 NULL（老行没有编辑时间，
      //    同步层据此判定胜负，见 sync_two_device_course_test 的老行用例）。
      final List<String> cols =
          (await v5.rawQuery('PRAGMA table_info(time_details)'))
              .map((Map<String, Object?> r) => r['name']!)
              .cast<String>()
              .toList();
      expect(cols, containsAll(<String>['created_time', 'modified_time']));
      final List<Map<String, Object?>> kept =
          await v5.query('time_details', orderBy: 'section ASC');
      expect(kept, hasLength(12), reason: '升级不得动掉存量作息行');
      expect(kept.first['start_minutes'], 480);
      expect(kept.last['end_minutes'], 525 + 11 * 55);
      expect(
        kept.where((Map<String, Object?> r) => r['modified_time'] == null).length,
        12,
        reason: '老行补的是 NULL，不是 0：0 会被当成 1970 年的编辑而恒判为旧',
      );
      final Map<String, Object?> meta = (await v5.query(
        '_meta',
        where: "key = 'applied_migration'",
        limit: 1,
      )).first;
      expect(meta['value'], '$kLatestSchemaVersion');
    } finally {
      await handle?.close();
      await tmp.delete(recursive: true);
    }
  });

  group('CHECK 约束', () {
    test('weekday 只收 1~7（ISO，周日 == 7；不接受 0 与 8）', () async {
      await expectRejected(env.db.insert('courses', courseRow(weekday: 0)));
      await expectRejected(env.db.insert('courses', courseRow(weekday: 8)));
      await expectLater(
          env.db.insert('courses', courseRow(weekday: 7)), completes);
    });

    test('end_section 不得小于 start_section（报错不交换的库层兜底）', () async {
      await expectRejected(
          env.db.insert('courses', courseRow(start: 5, end: 3)));
    });

    test('total_weeks 限 1~30', () async {
      await expectRejected(env.db.insert(
          'semesters',
          Semester(
            id: 's0',
            name: 'x',
            firstWeekMonday: DateTime.utc(2025, 9, 1),
            totalWeeks: 31,
          ).toMap()));
    });

    test('time_details 要求 end_minutes > start_minutes 且 section >= 1',
        () async {
      final TimeTable t = await env.semesterDao.createTimetable(name: '默认作息');
      await expectRejected(env.db.insert(
          'time_details',
          TimeDetail(
                  id: 'd1',
                  timetableId: t.id,
                  section: 1,
                  startMinutes: 500,
                  endMinutes: 500)
              .toMap()));
      await expectRejected(env.db.insert(
          'time_details',
          TimeDetail(
                  id: 'd2',
                  timetableId: t.id,
                  section: 0,
                  startMinutes: 480,
                  endMinutes: 525)
              .toMap()));
    });
  });

  test('同一作息表内节次唯一（UNIQUE(timetable_id, section)）', () async {
    final TimeTable t = await env.semesterDao.createTimetable(name: '默认作息');
    await env.db.insert(
        'time_details',
        TimeDetail(
                id: 'd1',
                timetableId: t.id,
                section: 1,
                startMinutes: 480,
                endMinutes: 525)
            .toMap());
    await expectRejected(env.db.insert(
        'time_details',
        TimeDetail(
                id: 'd2',
                timetableId: t.id,
                section: 1,
                startMinutes: 535,
                endMinutes: 580)
            .toMap()));
    // 不同作息表可以有第 1 节。
    final TimeTable other =
        await env.semesterDao.createTimetable(name: '冬令时');
    await expectLater(
        env.db.insert(
            'time_details',
            TimeDetail(
                    id: 'd3',
                    timetableId: other.id,
                    section: 1,
                    startMinutes: 480,
                    endMinutes: 525)
                .toMap()),
        completes);
  });

  group('外键语义（S6 同步落库顺序的依据）', () {
    test('课程引用不存在的学期 → 拒绝', () async {
      await expectRejected(
          env.db.insert('courses', courseRow(semesterId: 'nope')));
    });

    test('删学期 → 课程保留且 semester_id 置 NULL（SET NULL，不级联删课）',
        () async {
      final Semester s = await env.semesterDao.insert(
          name: '2025-2026-1', firstWeekMonday: DateTime.utc(2025, 9, 3));
      await env.courseDao
          .insert(Course(
            id: 'c1',
            uid: 'u1',
            name: '高等数学',
            weekday: 1,
            startSection: 1,
            endSection: 2,
            weeks: const <int>[1],
            semesterId: s.id,
          ));
      await env.db.delete('semesters',
          where: 'id = ?', whereArgs: <Object?>[s.id]);
      final Course? kept = await env.courseDao.findById('c1');
      expect(kept, isNotNull);
      expect(kept!.semesterId, isNull);
    });

    test('删作息表 → 其节次 CASCADE 清空', () async {
      final TimeTable t = await env.semesterDao.createTimetable(name: '默认作息');
      await env.db.insert(
          'time_details',
          TimeDetail(
                  id: 'd1',
                  timetableId: t.id,
                  section: 1,
                  startMinutes: 480,
                  endMinutes: 525)
              .toMap());
      await env.db.delete('timetables',
          where: 'id = ?', whereArgs: <Object?>[t.id]);
      expect(await env.semesterDao.findDetails(t.id), isEmpty);
    });
  });
}
