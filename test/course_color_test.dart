import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/features/course/course_color_picker.dart';
import 'package:qingdan/features/course/course_edit_panel.dart';
import 'package:qingdan/theme/app_palette.dart';
import 'package:qingdan/theme/app_theme.dart';

/// 课程配色（M6-D §十）：8 档 + 「自动」，并且**能真的清回 null**。
///
/// 最容易做错的是「改回自动」：`copyWith` 用 `??` 合并，传 null 等于没传，
/// 于是用户点了「自动」，列里还留着 5，改名后颜色不再跟着课名走——
/// 这条只有走到「保存出来的 Course」上才测得出来，所以本文件既测控件也测面板产物。
void main() {
  Course course({int? colorIndex, String name = '高等数学'}) => Course(
        id: 'c1',
        uid: 'u1',
        name: name,
        weekday: 1,
        startSection: 1,
        endSection: 2,
        weeks: const <int>[1, 2, 3],
        colorIndex: colorIndex,
      );

  Future<void> pump(WidgetTester tester, Widget child,
      {double width = 411}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String id) => find.byKey(ValueKey<String>(id));

  testWidgets('八档色点 + 自动；点第 5 号回调 5，点自动回调 null',
      (WidgetTester tester) async {
    final List<int?> picked = <int?>[];
    await pump(tester, CourseColorPicker(
        value: null, courseName: '高等数学', onChanged: picked.add));

    for (int i = 0; i < kCoursePaletteSize; i++) {
      expect(key('field-color-$i'), findsOneWidget, reason: '缺第 $i 号色点');
    }
    expect(key('field-color-auto'), findsOneWidget);
    expect(find.textContaining('自动（当前第'), findsOneWidget,
        reason: '自动档要显示它现在落到哪一色，否则用户以为那是「没颜色」');

    await tester.tap(key('field-color-5'));
    await tester.tap(key('field-color-auto'));
    await tester.pumpAndSettle();
    expect(picked, <int?>[5, null]);
  });

  testWidgets('选中态：value=3 时只有第 3 号带描边', (WidgetTester tester) async {
    await pump(tester,
        CourseColorPicker(value: 3, courseName: 'x', onChanged: (_) {}));
    // 选中态认「勾」而不是认描边宽度：描边是 BoxBorder，断言它的 width 既啰嗦
    // 又把测试钉在实现细节上（换个画法就红，行为其实没变）。
    expect(find.descendant(of: key('field-color-3'), matching: find.byIcon(Icons.check)),
        findsOneWidget);
    expect(find.descendant(of: key('field-color-4'), matching: find.byIcon(Icons.check)),
        findsNothing);
  });

  testWidgets('编辑面板：带着 colorIndex=5 打开时选中第 5 号',
      (WidgetTester tester) async {
    await pump(tester, CourseEditPanel(
        // 面板按端别走两套布局：411 必须配 isMobile（应用里就是这个配对）。
        // 「411 + 桌面分支」这个组合压根不存在，硬凑会撞到三列 stepper 在
        // 118dp 里放不下（第一版就是这么红的）。
        isMobile: true,
        totalWeeks: 20,
        maxSection: 12,
        initial: course(colorIndex: 5),
        onSave: (_) {}));
    expect(find.descendant(of: key('field-color-5'), matching: find.byIcon(Icons.check)),
        findsOneWidget);
  });

  testWidgets('★ 保存产物：点「自动」必须把列清成 null，而不是留着 5',
      (WidgetTester tester) async {
    Course? saved;
    await pump(tester, CourseEditPanel(
        isMobile: true,
        totalWeeks: 20,
        maxSection: 12,
        initial: course(colorIndex: 5),
        onSave: (Course c) => saved = c));

    await tester.tap(key('field-color-auto'));
    await tester.pumpAndSettle();
    await tester.tap(key('btn-save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull, reason: '保存按钮没触发，后面的断言都是空的');
    expect(saved!.colorIndex, isNull,
        reason: 'copyWith 的 `??` 会把 null 吞成旧值 → 这就是那个形状');
    expect(saved!.effectiveColorIndex, courseColorIndex('高等数学'));
    // 颜色不进 UID：改配色不该让下一次导入认成另一门课。
    expect(saved!.uid,
        courseUidOf(
            name: '高等数学',
            weekday: 1,
            startSection: 1,
            endSection: 2,
            weeks: const <int>[1, 2, 3]));
  });

  testWidgets('选第 2 号并保存：列里是 2，UID 不变', (WidgetTester tester) async {
    Course? saved;
    await pump(tester, CourseEditPanel(
        totalWeeks: 20,
        maxSection: 12,
        initial: course(),
        onSave: (Course c) => saved = c), width: 1280);

    await tester.tap(key('field-color-2'));
    await tester.pumpAndSettle();
    await tester.tap(key('btn-save'));
    await tester.pumpAndSettle();

    expect(saved!.colorIndex, 2);
    expect(saved!.effectiveColorIndex, 2);
    expect(CoursePalette.of(Brightness.light, 2) == CoursePalette.of(Brightness.light, 1),
        isFalse,
        reason: '色板本身要有区分度（对比度由 palette_contrast_test 钉）');
  });
}
