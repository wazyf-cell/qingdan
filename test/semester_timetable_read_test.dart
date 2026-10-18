import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/data/semester_dao.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane_model.dart';

import 'dao_test_helper.dart';

/// 学期作息**读路径**（2026-10-19 修的真机缺陷）。
///
/// 症状（真机库证实，见 `开发文档/01-变更日志/变更日志-2026-10-19-学期作息读路径.md`）：
/// 课表页的节次恒读 `semester_id IS NULL AND is_template = 0` 那张匿名老表，
/// 而 M6-D 之后**写路径按学期**（建学期即从模板复制一份该学期自己的作息行）。
/// 真机库里两个学期的作息各有 12 节，匿名表 `hnbxn5qq0400wzf` 一条都没有 →
/// 周视图永远显示「作息表还是空的」、全部课程落进「未排时间」。
///
/// 本文件钉住两条：① 按当前学期读；② 老库（学期没有自己的作息行）回落。
/// 界面侧的读写同表另见 `semester_timetable_read_ui_test.dart`。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb env;
  late SemesterUseCase semesters;
  late TimetableUseCase templates;
  late CourseUseCase courses;

  // 2025-09-01 是周一；时钟固定在第 2 周的周一，与作息内容无关。
  final DateTime mondayWeek1 = DateTime.utc(2025, 9, 1);
  final DateTime clock = DateTime.utc(2025, 9, 8);

  setUp(() async {
    env = await DaoTestDb.open();
    final AppServices services = AppServices(db: env.db);
    semesters = SemesterUseCase(services);
    templates = TimetableUseCase(services);
    courses = CourseUseCase(services);
  });
  tearDown(() async => env.close());

  CoursePaneModel model() => CoursePaneModel(
      semesterUseCase: semesters, courseUseCase: courses, clock: () => clock);

  TimeDetail row(int section, int start, int end) => TimeDetail(
      id: '',
      timetableId: '',
      section: section,
      startMinutes: start,
      endMinutes: end);

  /// 一套节次里的开始时间序列（断言只关心顺序与内容，不关心 id）。
  List<int> startsOf(List<TimeDetail> details) =>
      <int>[for (final TimeDetail d in details) d.startMinutes];

  test('① 课表页读当前学期**自己**的作息；切学期就换一套节次', () async {
    // 两套**不同**的作息模板：甲两节 08:00 起、乙三节 10:00 起。
    final TimeTable tplA = await templates.createTemplate(
        name: '甲表两节',
        generated: <TimeDetail>[row(1, 480, 525), row(2, 535, 580)]);
    final TimeTable tplB = await templates.createTemplate(
        name: '乙表三节',
        generated: <TimeDetail>[
          row(1, 600, 645),
          row(2, 655, 700),
          row(3, 710, 755)
        ]);
    final Semester a = await semesters.createSemester(
        name: '甲学期', firstWeekDate: mondayWeek1, totalWeeks: 4);
    final Semester b = await semesters.createSemester(
        name: '乙学期',
        firstWeekDate: mondayWeek1,
        totalWeeks: 4,
        setActive: false);
    await templates.applyTemplateToSemester(
        semesterId: a.id, templateId: tplA.id);
    await templates.applyTemplateToSemester(
        semesterId: b.id, templateId: tplB.id);
    // 匿名老表里**故意留一套「老内容」**（07:30 一节）：读路径一旦还盯着它，
    // 下面的断言就会拿到 [450] 而不是本学期的 [480, 535]。
    expect(await semesters.saveDefaultTimetable(<TimeDetail>[row(1, 450, 470)]),
        isNull);

    final CoursePaneModel m = model();
    await m.load();
    expect(m.error, isNull);
    expect(m.semester?.name, '甲学期');
    expect(startsOf(m.details), <int>[480, 535],
        reason: '甲学期自己的作息是 08:00 / 08:55 两节，不是匿名老表那一节');

    await m.switchSemester(b.id);
    expect(m.semester?.name, '乙学期');
    expect(startsOf(m.details), <int>[600, 655, 710],
        reason: '切到乙学期就必须换成乙学期自己的三节；还读到甲或匿名表都算没修');
  });

  test('② 老库回落：学期没有自己的作息行时读匿名默认表，不空不崩', () async {
    expect(await semesters.saveDefaultTimetable(<TimeDetail>[
      row(1, 480, 525),
      row(2, 535, 580),
    ]), isNull);
    // v6 之前建的学期：只插 semesters 行、没有配套作息行（DAO 直接建 = 老库形状）。
    final Semester legacy = await env.semesterDao.insert(
        name: '老库学期', firstWeekMonday: mondayWeek1, totalWeeks: 4);
    expect(await env.semesterDao.findTimetableForSemester(legacy.id), isNull,
        reason: '本条测的就是「该学期没有自己的作息行」这个前提');

    final CoursePaneModel m = model();
    await m.load();
    expect(m.error, isNull, reason: '回落不许抛，也不许把异常吞成空白页');
    expect(m.semester?.name, '老库学期');
    expect(startsOf(m.details), <int>[480, 535],
        reason: '老学期没有自己的作息时必须回落到匿名默认表，而不是返回空表');
  });

  test('②b 老库回落读写同表：该学期没有作息行时，保存也落在匿名默认表', () async {
    final Semester legacy = await env.semesterDao.insert(
        name: '老库学期', firstWeekMonday: mondayWeek1, totalWeeks: 4);
    final TimeTable anonymous = await semesters.ensureDefaultTimetable();
    expect(await env.semesterDao.findTimetableForSemester(legacy.id), isNull);

    expect(
        await semesters.saveDetailsForSemester(
            legacy.id, <TimeDetail>[row(1, 420, 460)]),
        isNull);
    expect(startsOf(await env.semesterDao.findDetails(anonymous.id)), <int>[420],
        reason: '回落必须是读写一起回落：读一张写另一张等于用户改了没生效');
    expect(await env.semesterDao.findTimetableForSemester(legacy.id), isNull,
        reason: '回落不该顺手给老学期补建一张作息行（那是迁移的事，不在读路径里做）');
  });
}
