// 界面侧的「学期作息读写同表」（2026-10-19 修读路径缺陷时一起处理的那条）。
//
// 覆盖两处读错 + 一处写错：
//   ③ 导入向导第 3 步：预览与编辑的节次必须属于**下拉选中的那个学期**，
//      不是恒取匿名老表（该步早已能选「导入到哪个学期」，读的还是老表）。
//   ④ 「学期与作息」弹层：卡里显示的是本学期自己的节次，保存也必须写回
//      **同一张表**。修之前显示与保存都落在匿名老表上（一起错位）；只修读
//      路径不修写路径的话，就会变成「显示本学期的、保存写进老表」——用户
//      改完点保存，重读还是旧值，等于 2026-10-18 那次「点了没反应」重演。
//
// 夹具一律在 `setUp` 里建（那里不在 FakeAsync 区，裸 await 才跑得完）；
// 按钮在假时钟区点，写链回 `runAsync` 轮询排干——本项目踩过多次挂死。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/data/semester_dao.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

import 'dao_test_helper.dart';
import 'semester_switcher_harness.dart';
import 'wizard_harness.dart';

TimeDetail _row(int section, int start, int end) => TimeDetail(
    id: '',
    timetableId: '',
    section: section,
    startMinutes: start,
    endMinutes: end);

List<int> _starts(List<TimeDetail> details) =>
    <int>[for (final TimeDetail d in details) d.startMinutes];

/// 作息卡里某一格当前显示的文本（`HH:MM`）。
String cellText(WidgetTester tester, int section, String tag) => tester
    .widget<TextField>(find.byKey(ValueKey<String>('time-$section-$tag')))
    .controller!
    .text;

void main() {
  ensureSqfliteFfi();

  group('③ 导入向导步 3 按选中的学期读', () {
    late WizardHarness h;

    setUp(() async => h = await WizardHarness.open(withSemester: false));
    tearDown(() async => h.close());

    testWidgets('选了哪个学期，节次就是哪个学期的（不是匿名老表）',
        (tester) async {
      await tester.runAsync(() async {
        // 匿名老表故意留一套 07:30：读路径还盯着它就一定露馅。
        await h.semesters.saveDefaultTimetable(<TimeDetail>[_row(1, 450, 470)]);
        final TimeTable tplA = await h.timetables.createTemplate(
            name: '甲表', generated: <TimeDetail>[_row(1, 480, 525)]);
        final TimeTable tplB = await h.timetables.createTemplate(
            name: '乙表',
            generated: <TimeDetail>[_row(1, 600, 645), _row(2, 655, 700)]);
        final Semester a = await h.semesters.createSemester(
            name: '甲学期',
            firstWeekDate: DateTime.utc(2025, 9, 1),
            totalWeeks: 16);
        final Semester b = await h.semesters.createSemester(
            name: '乙学期',
            firstWeekDate: DateTime.utc(2025, 9, 1),
            totalWeeks: 16,
            setActive: false);
        await h.timetables.applyTemplateToSemester(
            semesterId: a.id, templateId: tplA.id);
        await h.timetables.applyTemplateToSemester(
            semesterId: b.id, templateId: tplB.id);
        await h.pane.load();
      });

      await h.pumpWizard(tester,
          width: 1280,
          loadFile: h.csvLoader(scheduleCsv(<List<String>>[cells()])));
      await h.tapKey(tester, 'pick-file');
      await h.next(tester);
      await h.next(tester);
      expect(
          find.byKey(const ValueKey<String>('semester-save')), findsOneWidget,
          reason: '没走到步 3（学期与作息）');

      // 下拉默认选中的是当前学期（甲）→ 第 1 节该是甲自己的 08:00。
      expect(cellText(tester, 1, 'start'), '08:00',
          reason: '步 3 读的是本学期的作息；07:30 说明还在读那张匿名老表');

      // 换到非当前的乙学期：节次必须跟着换成乙的那一套。
      await tester.tap(find.byKey(const ValueKey<String>('adopt-semester')));
      await tester.pumpAndSettle();
      await h.tapText(tester, '乙学期 · 16 周');
      await tester.pumpAndSettle();
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pumpAndSettle();

      expect(cellText(tester, 1, 'start'), '10:00',
          reason: '预览用的节次必须属于**被选中的**那个学期');
      expect(find.byKey(const ValueKey<String>('time-2-start')), findsOneWidget,
          reason: '乙学期是两节表、甲学期只有一节：行数也要跟着换');
    });
  });

  group('④ 「学期与作息」弹层读写同一张表', () {
    late SemesterSwitcherHarness h;

    setUp(() async => h = await SemesterSwitcherHarness.open());
    tearDown(() async => h.close());

    testWidgets('改作息写的是当前学期自己的表；匿名老表一个字都不动',
        (tester) async {
      String semesterId = '';
      String anonymousId = '';
      await io(tester, () async {
        final Semester s = await h.semesters.createSemester(
            name: '甲学期',
            firstWeekDate: DateTime.utc(2025, 8, 4),
            totalWeeks: 16); // 建学期即从内置模板复制 12 节（08:00 起）
        semesterId = s.id;
        await h.semesters.saveDefaultTimetable(<TimeDetail>[_row(1, 450, 470)]);
        anonymousId = (await h.services.semesterDao.findDefaultTimetable())!.id;
        return 1;
      });
      await h.pumpAt(tester, width: 1280);

      await tester.tap(byKey('btn-setup'));
      await tester.pumpAndSettle();

      // 卡里显示的就是本学期第一节 08:00（匿名老表那一节 07:30 不该出现）。
      expect(cellText(tester, 1, 'start'), '08:00',
          reason: '弹层显示本学期自己的节次表；显示 07:30 = 还在读匿名老表');

      // 把第 1 节挪到 07:00（后面的节次按 §2.3 整体顺移）并保存。
      await tester.enterText(byKey('time-1-start'), '07:00');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(byKey('tt-save'));
      await tester.pump();
      await h.settle(tester, steps: 12);
      await tester.pumpAndSettle();

      final List<int>? own = await io(tester, () async {
        final TimeTable? t =
            await h.services.semesterDao.findTimetableForSemester(semesterId);
        if (t == null) return null;
        return _starts(await h.services.semesterDao.findDetails(t.id));
      });
      expect(own, isNotNull);
      expect(own!.first, 420,
          reason: '保存必须写进本学期自己的作息表（07:00 = 420 分）');

      final List<int>? anon = await io(tester,
          () async => _starts(await h.services.semesterDao
              .findDetails(anonymousId)));
      expect(anon, <int>[450],
          reason: '那张匿名老表（别的学期共用）不该被这次保存改动');
    });
  });
}
