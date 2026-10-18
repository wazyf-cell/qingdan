// 导入向导的闸门与校正语义（自 `import_wizard_test.dart` 按被测对象拆出，
// 断言一条未改）：✗ 行卡住「下一步」、忽略后不落库、步 3 能把导入指到非当前
// 学期、回跳到映射步先问「校正作废」。
//
// 双形态主路径在 `import_wizard_e2e_test.dart`，共用夹具在
// `import_wizard_harness.dart`（260ms 那一档等待时长照搬，未做任何调整）。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/features/course/import_wizard/wizard_file_picker.dart';

import 'dao_test_helper.dart';
import 'import_wizard_harness.dart';

void main() {
  ensureSqfliteFfi();

  late ImportWizardHarness h;
  // 以下本地位名只是把夹具接进本作用域，测试本体一字未改。
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late Uint8List xlsxBytes;

  setUp(() async {
    h = await ImportWizardHarness.open();
    semesters = h.semesters;
    courses = h.courses;
    xlsxBytes = h.xlsxBytes;
  });

  tearDown(() async => h.close());

  ScheduleFileLoader loader(Uint8List bytes, {String name = '课表模板.xlsx'}) =>
      h.loader(bytes, name: name);

  Future<void> openWizard(WidgetTester tester,
          {required double width,
          required ScheduleFileLoader loadFile}) =>
      h.openWizard(tester, width: width, loadFile: loadFile);

  Future<void> tapIo(WidgetTester tester, String key) => h.tapIo(tester, key);

  Future<void> next(WidgetTester tester) => h.next(tester);

  Future<void> tapTextIo(WidgetTester tester, String text) =>
      h.tapTextIo(tester, text);

  Future<List<Course>> readCourses(WidgetTester tester) =>
      h.readCourses(tester);

  Future<void> driveToCorrection(WidgetTester tester) =>
      h.driveToCorrection(tester);

  testWidgets('闸门：✗ 行未处理时下一步禁用；忽略后放行且不落库', (tester) async {
    final Uint8List csv = Uint8List.fromList(utf8.encode(
        '课程名称,星期,开始节数,结束节数,老师,地点,周数\n'
        '高等数学,1,1,2,小明,逸夫201,1-5\n'
        '大学体育,2,3,4,红哥,操场,1-5、约、7-11单\n'));
    await openWizard(tester, width: 1280, loadFile: loader(csv, name: 'a.csv'));
    await tapIo(tester, 'pick-file');
    await next(tester);
    await next(tester);
    await next(tester);

    expect(find.textContaining('还有 1 条错误未处理'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey<String>('wizard-next')))
            .onPressed,
        isNull,
        reason: '闸门没开就不给推进');

    await tapIo(tester, 'fix-3');
    await tester.pumpAndSettle();
    expect(find.text('忽略此条'), findsOneWidget, reason: '菜单没打开');
    await tapTextIo(tester, '忽略此条');

    await next(tester);
    await next(tester);
    final List<Course> saved = await readCourses(tester);
    expect(saved.map((Course c) => c.name), <String>['高等数学']);
  });

  testWidgets('步 3 学期下拉：导进非当前学期，扩周数落在那个学期（M6-D §7.5）',
      (tester) async {
    // B 学期不是当前学期：向导步 3 的下拉要能把导入目标指过去，
    // 之后建课 / 扩周数都必须落在 B 上（不再假设 active）。
    // 建学期是真异步写库，必须包在 runAsync 里：裸 await 在 FakeAsync 区域永不返回，
    // 整条测试会挂死而不是报错（本仓库 2026-10-19 就是这么卡了 8 分钟）。
    final String bId = (await tester
            .runAsync(() => semesters.createSemester(
                name: '第二学期',
                firstWeekDate: DateTime(2026, 3, 2),
                totalWeeks: 16,
                setActive: false)))!
        .id;
    final Uint8List csv = Uint8List.fromList(utf8.encode(
        '课程名称,星期,开始节数,结束节数,老师,地点,周数\n'
        '高等数学,1,1,2,小明,逸夫201,1-20\n'));
    await openWizard(tester, width: 1280, loadFile: loader(csv, name: 'b.csv'));
    await tapIo(tester, 'pick-file');
    await next(tester); // → 步 2
    await next(tester); // → 步 3

    expect(find.byKey(const ValueKey<String>('adopt-semester')), findsOneWidget,
        reason: '步 3 应有「导入到学期」下拉（§7.5 取代「沿用现有学期」）');
    await tapIo(tester, 'adopt-semester');
    await tapTextIo(tester, '第二学期 · 16 周');

    await next(tester); // → 步 4（buildRows 落在选中的 B 学期）
    expect(find.byKey(const ValueKey<String>('gate-banner')), findsOneWidget);
    await next(tester); // → 步 5
    await next(tester); // 开始导入 + 扩周数

    late List<Course> inB;
    await tester.runAsync(() async =>
        inB = await courses.activeCourses(semesterId: bId));
    expect(inB.map((Course c) => c.name), <String>['高等数学'],
        reason: '课程必须进选中的 B 学期');
    late List<Semester> all;
    await tester.runAsync(() async => all = await semesters.allSemesters());
    expect(all.firstWhere((Semester s) => s.id == bId).totalWeeks, 20,
        reason: '1-20 周的课要求把**选中学期**扩到 20 周');
    expect(all.firstWhere((Semester s) => s.isActive).totalWeeks, 16,
        reason: '当前学期不是导入目标，不许被扩');
  });

  testWidgets('回跳到映射步先问「校正作废」，确认后重算', (tester) async {
    await openWizard(tester,
        width: 1280, loadFile: loader(xlsxBytes));
    await tapIo(tester, 'pick-file');
    await driveToCorrection(tester);
    // 先忽略一行，制造「已做校正」
    await tapIo(tester, 'fix-3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('忽略此条'));
    await tester.pump();

    await tapIo(tester, 'step-1');
    expect(find.text('返回会丢失已做的校正'), findsOneWidget);
    await tapIo(tester, 'back-confirm');
    // 回到映射步，校正列表被清空（重进行 4 时才重算）
    expect(find.byKey(const ValueKey<String>('map-0')), findsOneWidget);
  });
}
