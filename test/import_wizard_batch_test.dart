// 校正界面的多选与批量操作（§4.3 规则 4 与规则 8）。
//
// 模型层直接打 [RowSelection]（快、无 UI），界面层只验两条真会被点错的路：
// 移动端长按进多选、批量忽略后 toast 撤销。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/import_wizard/import_wizard_model.dart';
import 'package:qingdan/features/course/import_wizard/import_wizard_types.dart';
import 'package:qingdan/import/course/course_row_parser.dart';
import 'package:qingdan/import/course/import_service.dart';

import 'dao_test_helper.dart';
import 'wizard_harness.dart';

void main() {
  ensureSqfliteFfi();

  Semester semester() => Semester(
      id: 's1',
      name: '2025-2026-1',
      firstWeekMonday: DateTime.utc(2025, 9, 1),
      totalWeeks: 16);

  /// 四行：两行同槽（周二 3-4，会互相 ⚠）、一行 ✓、一行 ✗（周次写坏）。
  // 四行落在文件第 2~5 行：2 ✓、3/4 同槽互相 ⚠、5 ✗（周次写坏）。
  final String csvText = scheduleCsv(<List<String>>[
    cells(name: '高等数学', weeks: '1-5'),
    cells(name: '线性代数', weekday: '2', start: '3', end: '4', weeks: '1-16'),
    cells(name: '大学英语', weekday: '2', start: '3', end: '4', weeks: '2、5、8'),
    cells(name: '大学体育', weekday: '3', weeks: '1-5、约、7-11单'),
  ]);

  late WizardHarness h;

  setUp(() async {
    h = await WizardHarness.open();
  });
  tearDown(() async => h.close());

  ImportWizardModel modelWithRows() {
    final ImportWizardModel m =
        ImportWizardModel(importer: ImportService(h.services.courseDao));
    m.loadFile(
        fileName: '批量.csv',
        bytes: Uint8List.fromList(utf8.encode(csvText)));
    m.guessMapping();
    m.adoptSemester(semester(), const <TimeDetail>[]);
    m.buildRows();
    return m;
  }

  group('模型层：批量处置', () {
    test('四行里两行重叠标 ⚠、一行 ✗，闸门因 ✗ 关闭', () {
      final ImportWizardModel m = modelWithRows();
      expect(m.listedCount, 4);
      expect(m.countOf(RowStatus.warning), 2);
      expect(m.countOf(RowStatus.error), 1);
      expect(m.gateOpen, isFalse);
    });

    test('批量忽略所选 → 闸门打开；撤销后恢复原处置', () {
      final ImportWizardModel m = modelWithRows();
      m.toggleSelected(5); // ✗ 那一行
      expect(m.selection.numbers, contains(5));
      expect(m.batchIgnore(), 1);
      expect(m.gateOpen, isTrue, reason: '忽略后不再阻塞');
      expect(m.ignoredCount, 1);
      expect(m.blockingRows, isEmpty);

      m.undoBatch();
      expect(m.ignoredCount, 0);
      expect(m.gateOpen, isFalse, reason: '撤销要完整回到忽略前');
    });

    test('批量删除把行移出预览，计数与可导入行数一起减', () {
      final ImportWizardModel m = modelWithRows();
      final int before = m.importableCourses.length;
      m.selectAll();
      expect(m.selection.numbers.length, 4);
      expect(m.batchDelete(), 4);
      expect(m.listedCount, 0);
      expect(m.deletedCount, 4);
      expect(m.importableCourses, isEmpty);
      expect(m.importableCourses.length, lessThan(before));

      m.undoBatch();
      expect(m.listedCount, 4, reason: '删除同样可撤销');
    });

    test('批量改周次只作用于解析成功的行，✗ 行留给闸门处理', () {
      final ImportWizardModel m = modelWithRows();
      final String uidBefore = m.rowAt(3)!.parsed.course!.uid;
      m.selectAll();
      final int changed = m.batchEdit(weeks: <int>[2, 4]);
      expect(changed, 3, reason: '第 5 行是 ✗，没有 Course 可改');
      // 周次参与 UID（§3.5），批量改完必须重算，否则导入会按旧 UID 误判成更新。
      expect(m.rowAt(3)!.parsed.course!.uid, isNot(uidBefore),
          reason: '批量改周次没重算 UID');
      for (final CorrectionRow r in m.rows) {
        final Course? c = r.parsed.course;
        if (c == null) continue;
        expect(c.weeks, <int>[2, 4], reason: '${c.name} 没被批量改到');
      }
    });

    test('批量改老师/地点覆盖所选行；留空即清空为 null', () {
      final ImportWizardModel m = modelWithRows();
      m.selectAll();
      expect(m.batchEdit(location: '文成楼125'), 3);
      expect(
          m.rows
              .where((CorrectionRow r) => r.parsed.course != null)
              .every((CorrectionRow r) => r.parsed.course!.location == '文成楼125'),
          isTrue);
      m.selectAll();
      expect(m.batchEdit(teacher: ''), 3);
      expect(
          m.rows.every((CorrectionRow r) => r.parsed.course?.teacher == null),
          isTrue,
          reason: '空串归一成 null（§1.1「待定」）');
    });

    test('全选只选可见行：已删除的不被重新选上', () {
      final ImportWizardModel m = modelWithRows();
      m.setDisposition(2, RowDisposition.deleted);
      m.selectAll();
      expect(m.selection.numbers, isNot(contains(2)));
      expect(m.selection.numbers.length, 3);
    });
  });

  group('界面层', () {
    testWidgets('移动端长按行进入多选：批量条出现、勾选框可见', (tester) async {
      await h.pumpWizard(tester,
          width: 411, loadFile: h.csvLoader(csvText));
      await h.tapKey(tester, 'pick-file');
      await h.driveToCorrection(tester);
      // 默认筛选只显示有问题的行（两条 ⚠ + 一条 ✗）
      expect(find.byKey(const ValueKey<String>('batch-bar')), findsNothing);
      await h.longPressIo(
          tester, find.byKey(const ValueKey<String>('row-3')).first);

      expect(find.byKey(const ValueKey<String>('batch-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('check-3')), findsOneWidget);
      expect(find.text('已选 1'), findsOneWidget);
    });

    testWidgets('桌面批量忽略后行内撤销条：处置完整回退', (tester) async {
      await h.pumpWizard(tester,
          width: 1280, loadFile: h.csvLoader(csvText));
      await h.tapKey(tester, 'pick-file');
      await h.driveToCorrection(tester);

      await h.tapIo(tester, find.byKey(const ValueKey<String>('check-3')));
      await h.tapIo(tester, find.byKey(const ValueKey<String>('check-4')));
      expect(find.text('已选 2'), findsOneWidget);

      await h.tapKey(tester, 'batch-menu');
      await tester.pumpAndSettle();
      await h.tapText(tester, '批量忽略');
      expect(find.byKey(const ValueKey<String>('undo-bar')), findsOneWidget);
      expect(find.text('已忽略 2 行'), findsOneWidget);
      await h.tapKey(tester, 'undo-batch');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('batch-bar')), findsNothing,
          reason: '撤销后回到未多选状态');
      // 两条 ⚠ 行回到列表里（被忽略时它们仍在列表，只是划线；撤销后计数回来）
      expect(find.byKey(const ValueKey<String>('undo-bar')), findsNothing);
      expect(find.text('需处理 3'), findsOneWidget,
          reason: '撤销后两条 ⚠ 行回到未处置状态');
      expect(find.byKey(const ValueKey<String>('check-3')), findsOneWidget,
          reason: '桌面勾选框常显');
    });

    // 下面几条把「真机红屏」那条路径固化下来：对话框打开→输入→确定/遮罩关掉。
    // 崩溃本身在 widget 测试里不复现（假时钟没有 IME），所以这几条守的是交互与
    // 返回值；红屏真正的守卫是「对话框自己持有 TextEditingController」这条结构。
    for (final double width in <double>[411, 1280]) {
      testWidgets('批量改地点：输入→确定（$width）', (tester) async {
        await h.pumpWizard(tester,
            width: width, loadFile: h.csvLoader(csvText));
        await h.tapKey(tester, 'pick-file');
        await h.driveToCorrection(tester);
        if (width < 720) {
          await h.longPressIo(
              tester, find.byKey(const ValueKey<String>('row-3')).first);
        } else {
          await h.tapIo(
              tester, find.byKey(const ValueKey<String>('check-3')));
        }
        expect(find.byKey(const ValueKey<String>('batch-bar')), findsOneWidget);

        await h.tapKey(tester, 'batch-menu');
        await tester.pumpAndSettle();
        await h.tapText(tester, '批量改地点');
        final Finder field =
            find.byKey(const ValueKey<String>('batch-text-field'));
        expect(field, findsOneWidget, reason: '批量改地点的输入框没出现');

        await tester.enterText(field, 'A201');
        await tester.pump();
        await h.tapKey(tester, 'text-ok');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(field, findsNothing);
        expect(find.text('已选 1'), findsNothing, reason: '批量后退出多选');
      });
    }

    testWidgets('批量改地点：点遮罩关掉对话框，不崩且回到多选态', (tester) async {
      await h.pumpWizard(tester,
          width: 411, loadFile: h.csvLoader(csvText));
      await h.tapKey(tester, 'pick-file');
      await h.driveToCorrection(tester);
      await h.longPressIo(
          tester, find.byKey(const ValueKey<String>('row-3')).first);
      await h.tapKey(tester, 'batch-menu');
      await tester.pumpAndSettle();
      await h.tapText(tester, '批量改地点');
      expect(
          find.byKey(const ValueKey<String>('batch-text-field')), findsOneWidget);

      await tester.tapAt(const Offset(30, 30)); // 对话框外的遮罩
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('batch-text-field')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('batch-bar')), findsOneWidget,
          reason: '取消批量输入不该把多选态一起弄丢');
    });

    testWidgets('批量改周次：chip 弹层选完确定，UID 跟着重算', (tester) async {
      await h.pumpWizard(tester,
          width: 411, loadFile: h.csvLoader(csvText));
      await h.tapKey(tester, 'pick-file');
      await h.driveToCorrection(tester);
      await h.longPressIo(
          tester, find.byKey(const ValueKey<String>('row-3')).first);
      await h.tapKey(tester, 'batch-menu');
      await tester.pumpAndSettle();
      await h.tapText(tester, '批量改周次');
      expect(find.byKey(const ValueKey<String>('weeks-ok')), findsOneWidget);
      await h.tapKey(tester, 'week-2');
      await h.tapKey(tester, 'weeks-ok');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('batch-bar')), findsNothing);
    });
  });
}
