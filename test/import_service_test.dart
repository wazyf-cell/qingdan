// 导入服务：三种模式的计划与单事务落库（`方案设计-课表域.md` §3.1 闸门、§3.5 模式）。
//
// 全程走真实内存库（不 mock DAO）：计划算得对不对，最终要看库里剩下什么。

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/import/course/import_service.dart';

import 'dao_test_helper.dart';

void main() {
  ensureSqfliteFfi();

  late DaoTestDb env;
  late ImportService service;
  late String semesterId;

  setUp(() async {
    env = await DaoTestDb.open();
    service = ImportService(env.courseDao);
    final Semester s = await env.semesterDao.insert(
        name: '2025-2026-1', firstWeekMonday: DateTime.utc(2025, 9, 1));
    semesterId = s.id;
  });

  tearDown(() async => env.close());

  /// 一行文件数据（uid 现场算，跟解析层产出的形状一致）。
  Course row({
    String name = '高等数学',
    int weekday = 1,
    int start = 1,
    int end = 2,
    List<int> weeks = const <int>[1, 2, 3],
    String? semesterId,
    String? teacher,
    String? location,
    CourseOrigin origin = CourseOrigin.import,
  }) =>
      Course(
        id: '',
        uid: courseUidOf(
            name: name,
            weekday: weekday,
            startSection: start,
            endSection: end,
            weeks: weeks),
        name: name,
        weekday: weekday,
        startSection: start,
        endSection: end,
        weeks: weeks,
        semesterId: semesterId,
        teacher: teacher,
        location: location,
        rawWeeksText: '1-3',
        origin: origin,
      );

  Future<List<Course>> active() => env.courseDao.findActive();

  Future<void> importRows(List<Course> rows, ImportMode mode) async {
    final ImportPlan plan =
        await service.plan(rows: rows, semesterId: semesterId, mode: mode);
    await service.apply(plan: plan, semesterId: semesterId, fileName: 'x.xlsx');
  }

  group('计划', () {
    test('文件内同 UID 的重复行只留第一条，其余计入 duplicated（§3.4 静默去重）',
        () async {
      final ImportPlan plan = await service.plan(
          rows: <Course>[row(location: 'A'), row(location: 'B')],
          semesterId: semesterId,
          mode: ImportMode.merge);
      expect(plan.insert, hasLength(1));
      expect(plan.duplicated, hasLength(1));
    });

    test('覆盖模式不做 diff：全部行进 insert，并预告将软删的条数', () async {
      await importRows(<Course>[row(name: '旧课')], ImportMode.merge);
      await env.courseDao.insert(
          row(name: '手动课', weekday: 3, semesterId: semesterId)
              .copyWith(origin: CourseOrigin.manual));

      final ImportPlan plan = await service.plan(
          rows: <Course>[row(name: '新课')],
          semesterId: semesterId,
          mode: ImportMode.overwrite);
      expect(plan.insert, hasLength(1));
      expect(plan.update, isEmpty);
      expect(plan.willRemoveImported, 1, reason: '一条导入课将被软删');
      expect(plan.activeManualCount, 1, reason: '红字里那句「手动不受影响」的数');
    });

    test('仅新增：库里已有的 UID 全进 skipped，不产生 update', () async {
      await importRows(<Course>[row()], ImportMode.merge);
      final ImportPlan plan = await service.plan(
          rows: <Course>[row(teacher: '换老师'), row(name: '线性代数', weekday: 2)],
          semesterId: semesterId,
          mode: ImportMode.appendOnly);
      expect(plan.skipped, hasLength(1));
      expect(plan.insert, hasLength(1));
      expect(plan.update, isEmpty);
    });
  });

  group('落库', () {
    test('合并：只覆盖非键字段，id / 创建时间 / 键字段全部保住', () async {
      await importRows(<Course>[row(teacher: '小明', location: '逸夫201')],
          ImportMode.merge);
      final Course before = (await active()).single;

      await importRows(<Course>[
        row(teacher: '小红', location: '逸夫302')
      ], ImportMode.merge);

      final List<Course> after = await active();
      expect(after, hasLength(1), reason: '合并不该长出新行');
      expect(after.single.id, before.id);
      expect(after.single.teacher, '小红');
      expect(after.single.location, '逸夫302');
      expect(after.single.createdTime, before.createdTime,
          reason: '以库中行为底改，created_time 不能被写没');
      expect(after.single.uid, before.uid);
    });

    test('合并：库里有、文件没有的 UID 不动（§3.5）', () async {
      await importRows(<Course>[row(name: '留下我'), row(name: '删掉我')],
          ImportMode.merge);
      await importRows(<Course>[row(name: '留下我')], ImportMode.merge);
      expect((await active()).map((Course c) => c.name), containsAll(<String>[
        '留下我',
        '删掉我'
      ]));
    });

    test('改周次 = UID 变 = 合并下新增一条，旧行原样留着（§3.5 明说的语义）',
        () async {
      await importRows(<Course>[row(weeks: <int>[1, 2, 3])], ImportMode.merge);
      await importRows(<Course>[row(weeks: <int>[1, 2, 3, 4])],
          ImportMode.merge);
      final List<Course> all = await active();
      expect(all, hasLength(2));
      expect(all.map((Course c) => c.weeks.length), containsAll(<int>[3, 4]));
    });

    test('覆盖：只软删 import 来源，手动课一条不少', () async {
      await env.courseDao.insert(
          row(name: '手动课', weekday: 4, semesterId: semesterId)
              .copyWith(origin: CourseOrigin.manual));
      await importRows(<Course>[row(name: '旧导入')], ImportMode.merge);
      expect(await active(), hasLength(2));

      await importRows(<Course>[row(name: '新导入')], ImportMode.overwrite);

      final List<Course> left = await active();
      expect(left.map((Course c) => c.name).toSet(),
          <String>{'手动课', '新导入'});
    });

    test('仅新增：已存在的行连字段都不改', () async {
      await importRows(<Course>[row(teacher: '小明')], ImportMode.merge);
      await importRows(<Course>[row(teacher: '别人')], ImportMode.appendOnly);
      expect((await active()).single.teacher, '小明');
    });

    test('批次计数如实：inserted / updated / skipped 与库内结果一致', () async {
      await importRows(<Course>[row(name: 'A'), row(name: 'B')],
          ImportMode.merge);
      final ImportPlan plan = await service.plan(
          rows: <Course>[
            row(name: 'A', teacher: '换了'),
            row(name: 'C'),
            row(name: 'C'), // 文件内重复
          ],
          semesterId: semesterId,
          mode: ImportMode.merge);
      await service.apply(
          plan: plan, semesterId: semesterId, fileName: '课表模板.xlsx');

      final List<Map<String, Object?>> batches =
          await env.db.query('import_batches', orderBy: 'rowid ASC');
      expect(batches, hasLength(2), reason: '前一步的导入也记了一批');
      final Map<String, Object?> last = batches.last;
      expect(last['count_imported'], 1, reason: '只有 C 是新行');
      expect(last['count_updated'], 1, reason: 'A 改了老师');
      expect(last['count_skipped'], 1, reason: '文件内重复那条');
    });

    test('批次簿记不写 op-log；课程写必须写 op-log', () async {
      await importRows(<Course>[row()], ImportMode.merge);
      expect(await env.opLog('import_batch'), isEmpty);
      expect(await env.opLog('course'), hasLength(1));
    });

    test('单事务：中途炸掉则一行都不落，op-log 也不留痕（§3.1 不留半截）',
        () async {
      final ImportPlan plan = await service.plan(
          rows: <Course>[row(name: '好的'), row(name: '星期越界', weekday: 9)],
          semesterId: semesterId,
          mode: ImportMode.merge);
      await expectLater(
          service.apply(
              plan: plan, semesterId: semesterId, fileName: 'x.xlsx'),
          throwsA(anything));
      expect(await active(), isEmpty, reason: '第一条必须跟着回滚');
      expect(await env.opLog('course'), isEmpty);
    });
  });
}
