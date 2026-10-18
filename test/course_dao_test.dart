import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

import 'dao_test_helper.dart';

/// 课程 / 学期 / 作息 DAO 测试（S1.3）。
///
/// 两条铁律在这里验：**写库与记 op-log 同一事务**（AGENTS.md）、
/// 周次过滤不能用 `LIKE '%3%'`（会把第 3 周和第 13、23 周一起捞出来）。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb env;
  setUp(() async => env = await DaoTestDb.open());
  tearDown(() async => env.close());

  Future<List<Map<String, Object?>>> opLog(String entityType) => env.db.query(
      'op_log',
      where: 'entity_type = ?', whereArgs: <Object?>[entityType]);

  Course course({
    String id = 'c1',
    List<int> weeks = const <int>[1, 2, 3],
    int weekday = 1,
    CourseOrigin origin = CourseOrigin.manual,
    String? semesterId,
    String? importBatchId,
  }) =>
      Course(
        id: id,
        uid: 'uid_$id',
        name: '高等数学$id',
        weekday: weekday,
        startSection: 1,
        endSection: 2,
        weeks: weeks,
        origin: origin,
        semesterId: semesterId,
        importBatchId: importBatchId,
      );

  group('课程读写', () {
    test('insert 同时留下 create op-log（同一事务的铁律）', () async {
      await env.courseDao.insert(course());
      final List<Map<String, Object?>> logs = await opLog('course');
      expect(logs, hasLength(1));
      expect(logs.single['operation'], 'create');
      expect(logs.single['entity_id'], 'c1');
    });

    test('findOnWeek 按周次精确命中，不被 JSON 子串误伤', () async {
      await env.courseDao.insert(course(weeks: <int>[1, 11, 13]));
      expect(await env.courseDao.findOnWeek(1), hasLength(1));
      expect(await env.courseDao.findOnWeek(11), hasLength(1));
      expect(await env.courseDao.findOnWeek(13), hasLength(1));
      // 第 3 周没课：`LIKE '%3%'` 的写法会在这里假命中。
      expect(await env.courseDao.findOnWeek(3), isEmpty);
      expect(await env.courseDao.findOnWeek(2), isEmpty);
    });

    test('update 只记真正变化的字段', () async {
      final Course saved = await env.courseDao.insert(course());
      await env.courseDao.update(saved.copyWith(location: '逸夫楼201'));
      final List<Map<String, Object?>> logs = await opLog('course');
      expect(logs, hasLength(2));
      expect(logs.last['operation'], 'update');
      expect(logs.last['changes_json']! as String, contains('location'));
      // 无变化再 update 一次：不应产生新日志。
      await env.courseDao.update(saved.copyWith(location: '逸夫楼201'));
      expect(await opLog('course'), hasLength(2));
    });

    test('softDelete 后不再出现在活跃查询里，countActive 同步减少', () async {
      await env.courseDao.insert(course());
      expect(await env.courseDao.countActive(), 1);
      await env.courseDao.softDelete('c1');
      expect(await env.courseDao.findActive(), isEmpty);
      expect(await env.courseDao.countActive(), 0);
      expect(await env.courseDao.findById('c1'), isNotNull); // 行还在
    });

    test('覆盖导入只软删 import 来源，手动创建的课不动（§3.5）', () async {
      final Semester s = await env.semesterDao.insert(
          name: '2025-2026-1', firstWeekMonday: DateTime.utc(2025, 9, 1));
      final ImportBatch batch = ImportBatch(
          id: 'b1',
          fileName: '课表模板.xlsx',
          importedAt: DateTime.now().toUtc());
      await env.courseDao.insertBatch(batch);
      await env.courseDao
          .insert(course(id: 'm1', semesterId: s.id));
      await env.courseDao.insert(course(
          id: 'i1',
          semesterId: s.id,
          origin: CourseOrigin.import,
          importBatchId: batch.id));
      await env.courseDao.insert(course(
          id: 'i2',
          semesterId: s.id,
          origin: CourseOrigin.import,
          importBatchId: batch.id));

      expect(await env.courseDao.softDeleteImported(semesterId: s.id), 2);
      final List<Course> left =
          await env.courseDao.findActive(semesterId: s.id);
      expect(left.map((Course c) => c.id), <String>['m1']);
    });

    test('批次簿记不写 op-log（本地簿记，不参与同步）', () async {
      await env.courseDao.insertBatch(ImportBatch(
          id: 'b1',
          fileName: 'x.xlsx',
          importedAt: DateTime.now().toUtc()));
      expect(await opLog('import_batch'), isEmpty);
      final List<Map<String, Object?>> rows =
          await env.db.query('import_batches');
      expect(rows, hasLength(1));
    });
  });

  group('学期与作息', () {
    test('建学期自动归一到该周周一（§2.1 用户可选任意一天）', () async {
      final Semester s = await env.semesterDao.insert(
          name: '2025-2026-1', firstWeekMonday: DateTime.utc(2025, 9, 3));
      expect(s.firstWeekMonday, DateTime.utc(2025, 9, 1));
      final Semester? active = await env.semesterDao.findActive();
      expect(active!.id, s.id);
      expect(active.totalWeeks, Semester.defaultTotalWeeks);
    });

    test('学期写入记 semester op-log', () async {
      await env.semesterDao.insert(
          name: 's', firstWeekMonday: DateTime.utc(2025, 9, 1));
      expect(await opLog('semester'), hasLength(1));
    });

    test('replaceDetails：新增/修改/删除各自记日志，且保留节次的 id 不变',
        () async {
      final TimeTable t =
          await env.semesterDao.createTimetable(name: '默认作息');
      await env.semesterDao.replaceDetails(t.id, <TimeDetail>[
        TimeDetail(
            id: '',
            timetableId: t.id,
            section: 1,
            startMinutes: 480,
            endMinutes: 525),
        TimeDetail(
            id: '',
            timetableId: t.id,
            section: 2,
            startMinutes: 535,
            endMinutes: 580),
      ]);
      final List<TimeDetail> first = await env.semesterDao.findDetails(t.id);
      expect(first.map((TimeDetail d) => d.section), <int>[1, 2]);
      expect(await opLog('time_detail'), hasLength(2));
      // v5 起每节都要有时间戳：字段级 LWW 拿它当比较基准，缺了就永远判本地胜。
      expect(first.every((TimeDetail d) =>
          d.createdTime != null && d.modifiedTime != null), isTrue);

      // 改第 1 节时间、删掉第 2 节、加一节第 3 节。
      await env.semesterDao.replaceDetails(t.id, <TimeDetail>[
        first[0].copyWith(startMinutes: 500, endMinutes: 545),
        TimeDetail(
            id: '',
            timetableId: t.id,
            section: 3,
            startMinutes: 590,
            endMinutes: 635),
      ]);
      final List<TimeDetail> after = await env.semesterDao.findDetails(t.id);
      expect(after.map((TimeDetail d) => d.section), <int>[1, 3]);
      // 同步侧的命门：第 1 节还是同一行（id 未变），否则合并会当成一删一增。
      expect(after.first.id, first[0].id);
      expect(after.first.startMinutes, 500);
      expect(after.first.createdTime, first[0].createdTime,
          reason: '改时间不能把 created_time 冲掉');
      expect(after.first.modifiedTime, isNotNull);

      final List<Map<String, Object?>> logs = await opLog('time_detail');
      // 断言各操作的**条数**而不是顺序：op_log 无排序保证，顺序断言是脆的。
      final Map<String, int> byOperation = <String, int>{};
      for (final Map<String, Object?> r in logs) {
        final String op = r['operation']! as String;
        byOperation[op] = (byOperation[op] ?? 0) + 1;
      }
      expect(byOperation, <String, int>{'create': 3, 'update': 1, 'delete': 1});
    });

    test('replaceDetails 无变化时不产生日志（幂等保存）', () async {
      final TimeTable t =
          await env.semesterDao.createTimetable(name: '默认作息');
      final List<TimeDetail> details = generateTimeDetails(
          timetableId: t.id,
          firstStartMinutes: 480,
          lessonMinutes: 45,
          breakMinutes: 10,
          sectionCount: 2);
      await env.semesterDao.replaceDetails(t.id, details);
      final int before = (await opLog('time_detail')).length;
      final List<TimeDetail> saved = await env.semesterDao.findDetails(t.id);
      await env.semesterDao.replaceDetails(t.id, saved);
      expect(await opLog('time_detail'), hasLength(before));
    });

    test('默认作息表按 semester_id IS NULL 取，且只认最早那张', () async {
      final TimeTable a =
          await env.semesterDao.createTimetable(name: '默认作息');
      final TimeTable? found = await env.semesterDao.findDefaultTimetable();
      expect(found!.id, a.id);
      // 专属作息表挂在真实学期下（外键要求父行先存在），不得抢走「默认」身份。
      final Semester s = await env.semesterDao.insert(
          name: '2025-2026-1', firstWeekMonday: DateTime.utc(2025, 9, 1));
      await env.semesterDao.createTimetable(name: '某学期专属', semesterId: s.id);
      expect((await env.semesterDao.findDefaultTimetable())!.id, a.id);
    });
  });
}
