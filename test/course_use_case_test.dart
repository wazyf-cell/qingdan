import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

import 'dao_test_helper.dart';

/// 用例层测试（F28 手工录入 + F30 配置 + F34 今日课）。
///
/// UI 只能走这里，所以「写库 + 记 op-log 同一事务」这条铁律也在这一层验。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb env;
  late SemesterUseCase semesters;
  late CourseUseCase courses;

  setUp(() async {
    env = await DaoTestDb.open();
    // 每个用例新建 AppServices（同一条内存连接），模拟「重启后重新装配」。
    semesters = SemesterUseCase(AppServices(db: env.db));
    courses = CourseUseCase(AppServices(db: env.db));
  });
  tearDown(() async => env.close());

  Future<Semester> newSemester({int totalWeeks = 16}) => semesters.createSemester(
      name: '2025-2026-1',
      firstWeekDate: DateTime.utc(2025, 9, 3),
      totalWeeks: totalWeeks);

  test('raiseSemesterWeeks：只抬「选中的那个学期」，当前学期不动（M6-D §7.5）',
      () async {
    final Semester a = await newSemester(); // active，16 周
    final Semester b = await semesters.createSemester(
        name: '第二学期',
        firstWeekDate: DateTime.utc(2025, 9, 1),
        totalWeeks: 16,
        setActive: false);

    final Semester? raised = await courses.raiseSemesterWeeks(b.id, 20);
    expect(raised, isNotNull);
    expect(raised!.totalWeeks, 20);
    final List<Semester> all = await semesters.allSemesters();
    expect(all.firstWhere((Semester s) => s.id == b.id).totalWeeks, 20);
    expect(all.firstWhere((Semester s) => s.id == a.id).totalWeeks, 16,
        reason: '导入目标是 B：扩周数不许顺手改到当前学期 A');
    expect(await courses.raiseSemesterWeeks(b.id, 20), isNull,
        reason: '同值再抬 = no-op');
    expect(await courses.raiseSemesterWeeks(b.id, 10), isNull,
        reason: '只抬不缩：缩周数会让已有课程翻不到');
  });

  test('F28 端到端：建学期 + 录作息 + 录一门课，重新装配后仍读得到', () async {
    final Semester s = await newSemester();
    expect(s.firstWeekMonday, DateTime.utc(2025, 9, 1),
        reason: '选了周三 9/3，应归一到该周周一（§2.1）');

    final String? error = await semesters.saveDefaultTimetable(<TimeDetail>[
      TimeDetail(
          id: '',
          timetableId: '',
          section: 1,
          startMinutes: 480,
          endMinutes: 525),
      TimeDetail(
          id: '',
          timetableId: '',
          section: 2,
          startMinutes: 535,
          endMinutes: 580),
    ]);
    expect(error, isNull);
    expect(await semesters.loadDefaultDetails(), hasLength(2));

    final Course created = await courses.create(
      name: '高等数学',
      weekday: 1,
      startSection: 1,
      endSection: 2,
      weeks: <int>[1, 2, 3],
      teacher: '小明',
      location: '逸夫楼201',
      semesterId: s.id,
    );
    expect(created.id, isNotEmpty);
    expect(created.origin, CourseOrigin.manual);
    expect(created.uid, hasLength(40));

    // 换一个 AppServices 实例重读：证明读的是库，不是内存对象。
    final CourseUseCase again = CourseUseCase(AppServices(db: env.db));
    final List<Course> all = await again.activeCourses(semesterId: s.id);
    expect(all, hasLength(1));
    expect(all.single.name, '高等数学');
    expect(all.single.weeks, <int>[1, 2, 3]);
  });

  test('写课程与记 op-log 同一事务：落库必然留痕', () async {
    final Semester s = await newSemester();
    await courses.create(
      name: '线性代数',
      weekday: 2,
      startSection: 3,
      endSection: 4,
      weeks: <int>[1],
      semesterId: s.id,
    );
    expect(await env.opLog('course'), hasLength(1));
    expect((await env.opLog('course')).single['operation'], 'create');
  });

  test('学期总周数越界直接拒绝，不静默夹取', () async {
    expect(() => newSemester(totalWeeks: 31), throwsA(isA<ArgumentError>()));
    expect(() => newSemester(totalWeeks: 0), throwsA(isA<ArgumentError>()));
    expect(await semesters.activeSemester(), isNull,
        reason: '被拒绝的学期不该已经落库');
  });

  test('学期名称为空拒绝', () async {
    expect(
        () => semesters.createSemester(
            name: '   ', firstWeekDate: DateTime.utc(2025, 9, 1)),
        throwsA(isA<ArgumentError>()));
  });

  test('作息校验不过时一行都不写（§2.3 保存校验）', () async {
    final String? error = await semesters.saveDefaultTimetable(<TimeDetail>[
      TimeDetail(
          id: '',
          timetableId: '',
          section: 1,
          startMinutes: 480,
          endMinutes: 525),
      TimeDetail(
          id: '',
          timetableId: '',
          section: 2,
          startMinutes: 500,
          endMinutes: 560),
    ]);
    expect(error, contains('重叠'));
    expect(await semesters.loadDefaultDetails(), isEmpty,
        reason: '校验失败不得留下半张表');
  });

  test('改键字段 → UID 变；只改地点 → UID 不变（§3.5 语义）', () async {
    final Semester s = await newSemester();
    final Course c = await courses.create(
      name: '大学英语',
      weekday: 3,
      startSection: 1,
      endSection: 1,
      weeks: <int>[1, 2],
      semesterId: s.id,
    );
    await courses.update(c.copyWith(location: '文成楼125'));
    Course reloaded = (await courses.activeCourses(semesterId: s.id)).single;
    expect(reloaded.location, '文成楼125');
    expect(reloaded.uid, c.uid, reason: '地点不是键，UID 不该动');

    await courses.update(reloaded.copyWith(weeks: <int>[1, 2, 3]));
    reloaded = (await courses.activeCourses(semesterId: s.id)).single;
    expect(reloaded.uid, isNot(c.uid), reason: '周次进 UID，改了就是另一门课');
  });

  test('非法输入被用例层挡住（星期 0、结束早于起始、空周次）', () async {
    expect(
        () => courses.create(
            name: 'x', weekday: 0, startSection: 1, endSection: 2, weeks: <int>[1]),
        throwsA(isA<ArgumentError>()));
    expect(
        () => courses.create(
            name: 'x', weekday: 1, startSection: 5, endSection: 3, weeks: <int>[1]),
        throwsA(isA<ArgumentError>()));
    expect(
        () => courses.create(
            name: 'x', weekday: 1, startSection: 1, endSection: 2, weeks: <int>[]),
        throwsA(isA<ArgumentError>()));
  });

  test('F34 今日课：按学期周次与星期命中，换周就没了', () async {
    final Semester s = await newSemester();
    await courses.create(
      name: '高等数学',
      weekday: 1, // 周一
      startSection: 1,
      endSection: 2,
      weeks: <int>[1],
      semesterId: s.id,
    );
    expect(await courses.coursesOn(DateTime.utc(2025, 9, 1)), hasLength(1));
    expect(await courses.coursesOn(DateTime.utc(2025, 9, 8)), isEmpty,
        reason: '第 2 周不上这门课');
    expect(await courses.coursesOn(DateTime.utc(2025, 9, 2)), isEmpty,
        reason: '周二没课');
  });

  test('没有激活学期 / 日期在学期外 → 今日课返回空而不是抛错', () async {
    expect(await courses.coursesOn(DateTime.utc(2025, 9, 1)), isEmpty);
    final Semester s = await newSemester(totalWeeks: 2);
    expect(await courses.coursesOn(DateTime.utc(2025, 12, 1)), isEmpty,
        reason: '第 14 周超出 2 周学期');
    expect(s.totalWeeks, 2);
  });

  test('delete 是软删：不再出现在活跃查询里，行仍在库里', () async {
    final Semester s = await newSemester();
    final Course c = await courses.create(
      name: '体育课',
      weekday: 5,
      startSection: 1,
      endSection: 2,
      weeks: <int>[1],
      semesterId: s.id,
    );
    await courses.delete(c.id);
    expect(await courses.activeCourses(semesterId: s.id), isEmpty);
    expect(await env.courseDao.findById(c.id), isNotNull);
  });
}
