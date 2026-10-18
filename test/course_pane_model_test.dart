import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane_model.dart';

import 'dao_test_helper.dart';

/// 周视图状态模型测试（F31 / F34）。时钟注入固定日期，不依赖真实时间。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb env;
  late SemesterUseCase semesters;
  late CourseUseCase courses;

  // 2025-09-01 是周一 = 第 1 周；2025-09-08 是第 2 周的周一。
  final DateTime mondayWeek1 = DateTime.utc(2025, 9, 1);
  DateTime clock = DateTime.utc(2025, 9, 8);

  setUp(() async {
    env = await DaoTestDb.open();
    final AppServices services = AppServices(db: env.db);
    semesters = SemesterUseCase(services);
    courses = CourseUseCase(services);
    clock = DateTime.utc(2025, 9, 8);
  });
  tearDown(() async => env.close());

  CoursePaneModel model() => CoursePaneModel(
      semesterUseCase: semesters, courseUseCase: courses, clock: () => clock);

  Future<Semester> semesterWithTimetable({int totalWeeks = 4}) async {
    final Semester s = await semesters.createSemester(
        name: '2025-2026-1',
        firstWeekDate: mondayWeek1,
        totalWeeks: totalWeeks);
    await semesters.saveDefaultTimetable(<TimeDetail>[
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
    return s;
  }

  test('load 后定位到今天所在周（第 2 周），并读出学期与作息', () async {
    await semesterWithTimetable();
    final CoursePaneModel m = model();
    await m.load();
    expect(m.loaded, isTrue);
    expect(m.error, isNull);
    expect(m.hasSemester, isTrue);
    expect(m.week, 2);
    expect(m.totalWeeks, 4);
    expect(m.details, hasLength(2));
    expect(m.todayInSemester, isTrue);
  });

  test('没有学期时不炸：空态由界面呈现', () async {
    final CoursePaneModel m = model();
    await m.load();
    expect(m.hasSemester, isFalse);
    expect(m.weekCourses, isEmpty);
    expect(m.error, isNull);
    expect(m.todayInSemester, isFalse);
    expect(m.todayCourses, isEmpty);
  });

  test('加载失败记进 error 且不抛（本视图失败不阻塞启动）', () async {
    final CoursePaneModel m = CoursePaneModel(
      semesterUseCase: _BoomSemesterUseCase(env.db),
      courseUseCase: courses,
      clock: () => clock,
    );
    await m.load();
    expect(m.error, contains('模拟加载失败'));
    expect(m.loaded, isTrue);
  });

  test('周边界：第 1 周禁 ‹、最后一周禁 ›，selectWeek 越界被夹住', () async {
    await semesterWithTimetable(totalWeeks: 3);
    final CoursePaneModel m = model();
    await m.load();

    await m.selectWeek(1);
    expect(m.canPrev, isFalse);
    expect(m.canNext, isTrue);
    await m.prevWeek();
    expect(m.week, 1, reason: '禁用时再按也不该跑到第 0 周');

    await m.selectWeek(3);
    expect(m.canNext, isFalse);
    await m.nextWeek();
    expect(m.week, 3);

    await m.selectWeek(99);
    expect(m.week, 3, reason: '越界夹到最后一周，不给空周');
    await m.selectWeek(-5);
    expect(m.week, 1);
  });

  test('coursesOn 只返回当天且本真的要上的课', () async {
    final Semester s = await semesterWithTimetable();
    await courses.create(
        name: '周一第2周的课',
        weekday: 1,
        startSection: 1,
        endSection: 2,
        weeks: <int>[2],
        semesterId: s.id);
    await courses.create(
        name: '周一别的周',
        weekday: 1,
        startSection: 1,
        endSection: 1,
        weeks: <int>[3],
        semesterId: s.id);
    await courses.create(
        name: '周二的课',
        weekday: 2,
        startSection: 1,
        endSection: 1,
        weeks: <int>[2],
        semesterId: s.id);

    final CoursePaneModel m = model();
    await m.load();
    expect(m.coursesOn(1).map((Course c) => c.name), <String>['周一第2周的课']);
    expect(m.coursesOn(2), hasLength(1));
    expect(m.coursesOn(7), isEmpty);
    expect(m.todayCourses.map((Course c) => c.name), <String>['周一第2周的课'],
        reason: '今天是第 2 周的周一');
  });

  test('groupsOn 把同槽课分到一组（渲染堆叠）', () async {
    final Semester s = await semesterWithTimetable();
    await courses.create(
        name: '线性代数',
        weekday: 2,
        startSection: 1,
        endSection: 2,
        weeks: <int>[2],
        semesterId: s.id);
    await courses.create(
        name: '大学英语',
        weekday: 2,
        startSection: 1,
        endSection: 2,
        weeks: <int>[2],
        semesterId: s.id);
    final CoursePaneModel m = model();
    await m.load();
    expect(m.groupsOn(2).single.courses, hasLength(2));
    expect(m.groupsOn(2).single.shareSections, closeTo(1, 1e-9));
  });

  test('节次超出作息表的课进「未排时间」，不被截断（§3.4）', () async {
    final Semester s = await semesterWithTimetable();
    await courses.create(
        name: '第 3-4 节的课',
        weekday: 1,
        startSection: 3,
        endSection: 4,
        weeks: <int>[2],
        semesterId: s.id);
    await courses.create(
        name: '正常课',
        weekday: 1,
        startSection: 1,
        endSection: 1,
        weeks: <int>[2],
        semesterId: s.id);
    final CoursePaneModel m = model();
    await m.load();
    expect(m.unscheduled.map((Course c) => c.name), <String>['第 3-4 节的课']);
    expect(m.layout.missingSections(3, 4), <int>[3, 4]);
  });

  test('goToday 从别周跳回今天那一周', () async {
    await semesterWithTimetable();
    final CoursePaneModel m = model();
    await m.load();
    await m.selectWeek(4);
    expect(m.week, 4);
    await m.goToday();
    expect(m.week, 2);
  });

  test('周末折叠：移动默认 5 天、可展开 7 天；桌面恒 7 天', () async {
    await semesterWithTimetable();
    final CoursePaneModel m = model();
    await m.load();
    expect(m.visibleDays(isMobile: true), <int>[1, 2, 3, 4, 5]);
    m.toggleWeekend();
    expect(m.visibleDays(isMobile: true), <int>[1, 2, 3, 4, 5, 6, 7]);
    expect(m.visibleDays(isMobile: false), <int>[1, 2, 3, 4, 5, 6, 7]);
  });

  test('dateOf 与 weekMonday 一致（星期轴表头用）', () async {
    await semesterWithTimetable();
    final CoursePaneModel m = model();
    await m.load();
    expect(m.weekMonday, DateTime.utc(2025, 9, 8));
    expect(m.dateOf(1), DateTime.utc(2025, 9, 8));
    expect(m.dateOf(7), DateTime.utc(2025, 9, 14));
  });
}

/// 会抛的学期用例：验证模型的错误处理路径。
class _BoomSemesterUseCase extends SemesterUseCase {
  _BoomSemesterUseCase(Database db) : super(AppServices(db: db));

  @override
  Future<Semester?> activeSemester() async =>
      throw StateError('模拟加载失败');
}
