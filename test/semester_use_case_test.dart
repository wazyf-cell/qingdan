import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/data/semester_dao.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/default_timetable.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

import 'dao_test_helper.dart';

/// 学期用例（M6-D §6.1）：建学期 = 同事务「学期 → 作息 → 从模板复制节次」；
/// 删学期 = 同事务四类物理删 + 四类 delete 意图；当前学期切换永不记 op-log。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb env;
  late AppServices services;
  late SemesterUseCase semesters;
  late TimetableUseCase templates;

  setUp(() async {
    env = await DaoTestDb.open();
    services = AppServices(db: env.db);
    semesters = SemesterUseCase(services);
    templates = TimetableUseCase(services);
  });
  tearDown(() async => env.close());

  Future<List<Map<String, Object?>>> ops(String entityType, String operation) =>
      env.db.query('op_log',
          where: 'entity_type = ? AND operation = ?',
          whereArgs: <Object?>[entityType, operation],
          orderBy: 'rowid ASC');

  Future<List<String>> activeIds() async {
    final List<Map<String, Object?>> rows =
        await env.db.query('semesters', where: 'is_active = 1');
    return [for (final Map<String, Object?> r in rows) r['id']! as String];
  }

  Future<int> totalOpLog() async => (await env.db.query('op_log')).length;

  Future<Semester> makeSemester(
    String name, {
    String? templateId,
    bool setActive = false,
  }) =>
      semesters.createSemester(
        name: name,
        firstWeekDate: DateTime.utc(2026, 2, 2),
        templateId: templateId ?? kBuiltInTimetableId,
        setActive: setActive,
      );

  group('createSemester（§6.1 同事务三步）', () {
    test('学期 → 学期专属作息 → 从模板复制节次，op-log 三类 create 齐', () async {
      final Semester s = await semesters.createSemester(
          name: '2026春', firstWeekDate: DateTime.utc(2026, 2, 2));
      expect(s.name, '2026春');
      final TimeTable? table =
          await env.semesterDao.findTimetableForSemester(s.id);
      expect(table, isNotNull, reason: '学期必须有自己的专属作息行');
      expect(table!.name, '2026春 作息', reason: '§6.1 定名「<学期名> 作息」');
      expect(table.semesterId, s.id);
      expect(table.isTemplate, isFalse);
      final List<TimeDetail> details = await env.semesterDao.findDetails(table.id);
      expect(details, hasLength(kBuiltInTimeDetails.length),
          reason: '内置模板的 12 节要整表复制过来');
      expect(details.first.section, 1);
      expect(details.first.startMinutes, 480);
      expect(await ops('semester', 'create'), hasLength(1));
      expect(await ops('timetable', 'create'), hasLength(1));
      expect(await ops('time_detail', 'create'), hasLength(12));
    });

    test('复制的是快照：改模板不影响已建学期', () async {
      final TimeTable tpl = await templates.createTemplate(
        name: '两节作息',
        generated: <TimeDetail>[
          TimeDetail(id: '', timetableId: '', section: 1, startMinutes: 480, endMinutes: 525),
          TimeDetail(id: '', timetableId: '', section: 2, startMinutes: 540, endMinutes: 585),
        ],
      );
      final Semester s = await makeSemester('快照学期', templateId: tpl.id);
      final TimeTable own = (await env.semesterDao.findTimetableForSemester(s.id))!;
      final List<TimeDetail> before = await env.semesterDao.findDetails(own.id);
      expect(before.map((TimeDetail d) => d.startMinutes), <int>[480, 540]);

      // 改模板：第 1 节推到 500 开始。
      expect(
          await templates.saveTemplateDetails(tpl.id, <TimeDetail>[
            TimeDetail(id: '', timetableId: tpl.id, section: 1, startMinutes: 500, endMinutes: 545),
            TimeDetail(id: '', timetableId: tpl.id, section: 2, startMinutes: 560, endMinutes: 605),
          ]),
          isNull);

      final List<TimeDetail> after = await env.semesterDao.findDetails(own.id);
      expect(after.map((TimeDetail d) => d.startMinutes), <int>[480, 540],
          reason: '学期拿的是复制的快照，模板此后与它无关');
      expect(after.map((TimeDetail d) => d.id).toSet().intersection(
              (await env.semesterDao.findDetails(tpl.id))
                  .map((TimeDetail d) => d.id)
                  .toSet()),
          isEmpty,
          reason: '节次行是新 id，不是引用同一批模板行');
    });

    test('模板不存在时整事务回滚，不留半截学期', () async {
      final int semestersBefore = (await env.db.query('semesters')).length;
      await expectLater(
        semesters.createSemester(
            name: '坏引用',
            firstWeekDate: DateTime.utc(2026, 2, 2),
            templateId: 'no-such-template'),
        throwsA(isA<StateError>().having((StateError e) => e.message,
            'message', contains('no-such-template'))),
      );
      expect((await env.db.query('semesters')).length, semestersBefore);
      expect(await env.db.query('timetables', where: 'is_template = 0'), isEmpty,
          reason: '事务回滚：作息行与节次也不能留下');
    });

    test('setActive 默认 true 把当前学期切过去；false 不抢（DDL 默认 1 陷阱）', () async {
      final Semester s1 =
          await semesters.createSemester(name: '一', firstWeekDate: DateTime.utc(2025, 9, 1));
      expect(await activeIds(), <String>[s1.id], reason: '第一个学期恒为当前');
      final Semester s2 = await semesters.createSemester(
          name: '二', firstWeekDate: DateTime.utc(2026, 2, 2));
      expect(await activeIds(), <String>[s2.id], reason: '默认 setActive=true');
      await makeSemester('三');
      expect(await activeIds(), <String>[s2.id],
          reason: 'setActive=false 不抢当前（清旧留新，active 恒只有一个）');
      final Semester s4 = await semesters.createSemester(
          name: '四', firstWeekDate: DateTime.utc(2026, 2, 2));
      expect(await activeIds(), <String>[s4.id]);
      expect((await semesters.allSemesters()).length, 4);
    });

    test('周数越界拒绝不静默夹取，名称空拒绝', () async {
      await expectLater(
          semesters.createSemester(
              name: ' ', firstWeekDate: DateTime.utc(2026, 2, 2)),
          throwsA(isA<ArgumentError>()));
      await expectLater(
          semesters.createSemester(
              name: '超界', firstWeekDate: DateTime.utc(2026, 2, 2), totalWeeks: 31),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('setActiveSemester / deleteSemester（§6.1）', () {
    test('setActiveSemester 切换当前学期且不写 op-log（is_active 是本地列）', () async {
      final Semester s1 =
          await semesters.createSemester(name: '一', firstWeekDate: DateTime.utc(2025, 9, 1));
      final Semester s2 = await makeSemester('二');
      final int before = await totalOpLog();
      await semesters.setActiveSemester(s1.id);
      expect(await activeIds(), <String>[s1.id]);
      expect(await totalOpLog(), before,
          reason: '§四：记意图只会产生一条被剔成空白的变更，必须一条都不多');
      await semesters.setActiveSemester(s2.id);
      expect(await activeIds(), <String>[s2.id]);
      expect(await totalOpLog(), before);
    });

    test('deleteSemester 同事务物理删课/节次/作息/学期，四类 delete 意图齐', () async {
      final Semester keep = await makeSemester('留着的');
      final Semester gone = await makeSemester('删掉的');
      final TimeTable table = (await env.semesterDao.findTimetableForSemester(gone.id))!;
      final int detailCount = (await env.semesterDao.findDetails(table.id)).length;
      for (final String id in <String>['d1', 'd2']) {
        await env.courseDao.insert(Course(
          id: id, uid: 'uid_$id', name: '课$id', weekday: 1,
          startSection: 1, endSection: 2, weeks: <int>[1],
          origin: CourseOrigin.manual, semesterId: gone.id,
        ));
      }
      await env.courseDao.insert(Course(
        id: 'd3', uid: 'uid_d3', name: '软删的课', weekday: 2,
        startSection: 1, endSection: 2, weeks: <int>[1],
        origin: CourseOrigin.manual, semesterId: gone.id, deleted: true,
      ));
      await env.courseDao.insert(Course(
        id: 'keep', uid: 'uid_keep', name: '别的学期的课', weekday: 3,
        startSection: 1, endSection: 2, weeks: <int>[1],
        origin: CourseOrigin.manual, semesterId: keep.id,
      ));
      expect(await semesters.courseCountForDeletion(gone.id), 3,
          reason: '确认框的连带数量含软删行（物理删不挑 deleted）');

      await semesters.deleteSemester(gone.id);

      expect(await env.db.query('courses', where: 'semester_id = ?', whereArgs: <Object?>[gone.id]), isEmpty);
      expect(await env.db.query('time_details', where: 'timetable_id = ?', whereArgs: <Object?>[table.id]), isEmpty);
      expect(await env.db.query('timetables', where: 'id = ?', whereArgs: <Object?>[table.id]), isEmpty);
      expect(await env.db.query('semesters', where: 'id = ?', whereArgs: <Object?>[gone.id]), isEmpty);
      expect((await env.db.query('courses', where: 'semester_id = ?', whereArgs: <Object?>[keep.id])),
          hasLength(1), reason: '别的学期一门都不许掉');
      expect(await ops('course', 'delete'), hasLength(3));
      expect(await ops('time_detail', 'delete'), hasLength(detailCount));
      expect(await ops('timetable', 'delete'), hasLength(1));
      expect(await ops('semester', 'delete'), hasLength(1));
    });

    test('软删课程行也要被物理清走并记意图（漏记 = 另一端复活）', () async {
      // 上一条已覆盖 deleted=1 行（d3 计进 3 条 delete）；这里钉 op-log 的 delete
      // 指向的正是那个软删 id。
      await makeSemester('陪跑的'); // 至少保留一个学期的闸，删 target 时得有别人
      final Semester gone = await makeSemester('软删检查');
      await env.courseDao.insert(Course(
        id: 'x1', uid: 'uid_x1', name: '软删', weekday: 1,
        startSection: 1, endSection: 2, weeks: <int>[1],
        origin: CourseOrigin.manual, semesterId: gone.id, deleted: true,
      ));
      await semesters.deleteSemester(gone.id);
      final List<Map<String, Object?>> deletes = await ops('course', 'delete');
      expect(deletes.map((Map<String, Object?> r) => r['entity_id']), contains('x1'));
    });

    test('只剩一个学期时拒删，且不动一行、不记一条意图', () async {
      final Semester only = await makeSemester('独苗');
      final int before = await totalOpLog();
      await expectLater(
        semesters.deleteSemester(only.id),
        throwsA(isA<StateError>().having(
            (StateError e) => e.message, 'message', '至少保留一个学期')),
      );
      expect((await env.db.query('semesters')), hasLength(1));
      expect(await totalOpLog(), before);
    });

    test('删的是当前学期 → 剩下 created_time 最新的一个自动置 active 且不记 op-log', () async {
      final Semester s1 = await makeSemester('早的');
      final Semester s2 = await makeSemester('中');
      final Semester s3 = await makeSemester('晚的');
      // created_time 用毫秒时钟，三条可能同毫秒——显式钉死顺序再验「取最新」。
      await env.db.rawUpdate('UPDATE semesters SET created_time = 100 WHERE id = ?', <Object?>[s1.id]);
      await env.db.rawUpdate('UPDATE semesters SET created_time = 200 WHERE id = ?', <Object?>[s2.id]);
      await env.db.rawUpdate('UPDATE semesters SET created_time = 300 WHERE id = ?', <Object?>[s3.id]);
      await semesters.setActiveSemester(s2.id);
      final int before = await totalOpLog();
      final int detailCount =
          (await env.semesterDao.findDetails((await env.semesterDao.findTimetableForSemester(s2.id))!.id)).length;

      await semesters.deleteSemester(s2.id);

      expect(await activeIds(), <String>[s3.id],
          reason: '剩下的 s1/s3 里取 created_time 最新的 s3');
      final List<Map<String, Object?>> after = await env.db.query('op_log',
          orderBy: 'rowid ASC');
      final List<Map<String, Object?>> newOnes = after.skip(before).toList();
      expect(newOnes, hasLength(1 + detailCount + 1),
          reason: '只有 semester/time_detail/timetable 的 delete，setActive 的翻转必须零记录');
      expect(newOnes.map((Map<String, Object?> r) => r['operation']).toSet(),
          <String>{'delete'});
    });
  });
}
