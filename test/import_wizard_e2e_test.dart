// 导入向导端到端主路径（F29/F30/F31 的验收主战场；自 `import_wizard_test.dart`
// 按被测对象拆出，断言一条未改）。
//
// **两种形态各跑一遍**（S4b 的教训：只 pump 桌面壳，手机上四处布局全炸）。
// 全程点界面，不直接调用例层；文件用仓库里的真实 xlsx 样本。
//
// 闸门 / 步 3 导入目标学期 / 回跳作废那三条在
// `import_wizard_gate_correction_test.dart`，共用夹具在 `import_wizard_harness.dart`。

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/features/course/import_wizard/wizard_file_picker.dart';

import 'dao_test_helper.dart';
import 'import_wizard_harness.dart';

void main() {
  ensureSqfliteFfi();

  late ImportWizardHarness h;
  // 以下本地位名只是把夹具接进本作用域，测试本体一字未改。
  late Uint8List xlsxBytes;

  setUp(() async {
    h = await ImportWizardHarness.open();
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

  Future<List<Course>> readCourses(WidgetTester tester) =>
      h.readCourses(tester);

  Future<void> driveToCorrection(WidgetTester tester) =>
      h.driveToCorrection(tester);

  testWidgets('桌面端到端：真实 xlsx → 映射 → 校正 → 合并导入 3 条落库',
      (tester) async {
    await openWizard(tester,
        width: 1280, loadFile: loader(xlsxBytes));

    // 步 1：编码结论行必须显式（§3.1:162）
    await tapIo(tester, 'pick-file');
    expect(find.textContaining('已按'), findsOneWidget);
    expect(find.textContaining('7 列、3 行'), findsOneWidget);
    await driveToCorrection(tester);

    // 默认筛选 = 只看有问题的（§4.3 规则 5）：✓ 行（文件第 2 行高数）不该出现，
    // 重叠的两条（第 3、4 行）出现。
    expect(find.byKey(const ValueKey<String>('row-2')), findsNothing,
        reason: '✓ 正常行默认不显示');
    expect(find.byKey(const ValueKey<String>('row-3')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('gate-banner')), findsOneWidget,
        reason: '确认已经走到步 4');

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey<String>('filter-all')));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('row-2')), findsOneWidget);

    // 步 5：首次导入隐藏模式选择（§3.1:166），直接合并
    await next(tester);
    expect(find.byKey(const ValueKey<String>('mode-hidden')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('mode-overwrite')), findsNothing);
    await next(tester); // 开始导入
    expect(find.byKey(const ValueKey<String>('import-summary')), findsOneWidget);
    expect(find.textContaining('新增 3'), findsOneWidget);

    final List<Course> saved = await readCourses(tester);
    expect(saved, hasLength(3));
    expect(saved.map((Course c) => c.name).toSet(),
        <String>{'高等数学', '线性代数', '大学英语'});
    // 高数：1-5、7-11单、12-16双 → 绝对奇偶周号（§3.3.1）
    final Course gao =
        saved.firstWhere((Course c) => c.name == '高等数学');
    expect(gao.weeks, containsAll(<int>[9, 11, 12, 14, 16]));
    expect(gao.origin, CourseOrigin.import);
  });

  testWidgets('移动端 411dp 同一条路：卡片列表，无表头，导入同样落库',
      (tester) async {
    await openWizard(tester,
        width: 411, loadFile: loader(xlsxBytes));
    expect(find.byKey(const ValueKey<String>('wizard-back')), findsNothing,
        reason: '步 1 不给上一步');
    await tapIo(tester, 'pick-file');
    await driveToCorrection(tester);

    // 移动形态：卡片列表（没有桌面表头），行仍可点（点开底部抽屉编辑器）
    expect(find.text('状态 / 课程'), findsNothing);
    expect(find.byKey(const ValueKey<String>('row-3')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('gate-banner')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('row-3')));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsOneWidget,
        reason: '移动端点行 → 底部抽屉承载同一个编辑面板');
    await tester.tap(find.byKey(const ValueKey<String>('field-location')));
    await tester.enterText(
        find.byKey(const ValueKey<String>('field-location')), '理工楼110');
    await tester.tap(find.byKey(const ValueKey<String>('btn-save')));
    await tester.pumpAndSettle();

    await next(tester);
    await next(tester);
    expect(find.byKey(const ValueKey<String>('import-summary')), findsOneWidget);
    expect(await readCourses(tester), hasLength(3));
  });
}
