import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/export_sheet.dart';
import 'package:qingdan/theme/app_theme.dart';

/// §9.2 导出弹层。双端各 pump 一次（411 与 1280）——M4a 的教训：只跑桌面宽度
/// 等于没测移动端。保存动作用注入的假 saver，平台写文件由 file_intents_test 管。
void main() {
  // 学期名故意带 `/` 与空格，钉死文件名消毒。
  final Semester semester = Semester(
    id: 'sem-1',
    name: '2026/秋季 学期',
    firstWeekMonday: DateTime.utc(2026, 10, 19),
    totalWeeks: 4,
  );

  /// 从 08:00 起、每节 45 分钟的前 [count] 节（与 ics_writer_test 同款夹具）。
  List<TimeDetail> sections(int count) => <TimeDetail>[
        for (int s = 1; s <= count; s++)
          TimeDetail(
            id: 'tt-$s',
            timetableId: 'tt-1',
            section: s,
            startMinutes: 480 + (s - 1) * 55,
            endMinutes: 525 + (s - 1) * 55,
          ),
      ];
  final List<TimeDetail> four = sections(4);

  Course c(String name, int weekday, int start, int end, List<int> weeks) =>
      Course(
        id: 'c-$name',
        uid: 'uid-$name',
        name: name,
        weekday: weekday,
        startSection: start,
        endSection: end,
        weeks: weeks,
        semesterId: semester.id,
      );

  final List<Course> courses = <Course>[
    c('高等数学', 1, 1, 2, <int>[1, 2, 3, 4]), // 4 个事件（ics）
    c('英语', 2, 3, 4, <int>[1]), // 1 个
    c('越界实验', 3, 2, 9, <int>[1, 2]), // 第 9 节不在作息表 → ics 跳过
    c('体育', 5, 1, 1, <int>[2, 3]), // 不在第 1 周 → 「仅本周」时被裁掉
  ];

  Future<void> openSheet(WidgetTester tester,
      {required double width, required ExportSaver saver}) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      // 必须走 AppTheme：AppColors.of 读的是它装的 ThemeExtension。
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            key: const Key('open'),
            onPressed: () => showExportSheet(context,
                semester: semester,
                courses: courses,
                details: four,
                currentWeek: 1,
                isMobile: width < 720,
                saver: saver),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('export-sheet')), findsOneWidget);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
  }

  String countText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey<String>('export-count'))).data!;

  /// 两种形态跑同一段断言（411 底部抽屉 / 1280 居中弹窗）。
  void sheetShape(String label, double width) {
    testWidgets('$label：计数随格式与范围变化，跳过提示只在 ics 出现',
        (WidgetTester tester) async {
      await openSheet(tester, width: width, saver: (m, f, b) async => const ExportOutcome.canceled());

      // 初始 ics + 全部周：4 门课；事件 4+1+2=7（越界实验被跳）；跳过提示 1。
      expect(countText(tester), '将导出 4 门课程、7 个事件');
      expect(find.byKey(const ValueKey<String>('export-skipped')),
          findsOneWidget);
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey<String>('export-skipped')))
              .data,
          '1 门课因节次不在作息表中被跳过');

      await tapKey(tester, 'export-scope-week'); // 仅本周
      expect(countText(tester), '将导出 3 门课程、2 个事件');

      await tapKey(tester, 'export-format-csv'); // csv：一行 == 一个事件
      expect(countText(tester), '将导出 3 门课程、3 个事件');
      expect(find.byKey(const ValueKey<String>('export-skipped')), findsNothing);

      await tapKey(tester, 'export-scope-all');
      expect(countText(tester), '将导出 4 门课程、4 个事件');
    });
  }

  sheetShape('窄屏 411', 411);
  sheetShape('桌面 1280', 1280);

  testWidgets('导出按钮：文件名消毒 + mime + 字节送达 saver；回执显示完整路径与复制按钮',
      (WidgetTester tester) async {
    final _FakeSave fake = _FakeSave();
    await openSheet(tester, width: 411, saver: fake.call);
    await tapKey(tester, 'export-run');

    expect(fake.fileName, '2026_秋季_学期.ics'); // `/` 与空格都换成了下划线
    expect(fake.mime, 'text/calendar');
    expect(utf8.decode(fake.bytes!.take(15).toList()), 'BEGIN:VCALENDAR');

    const String path =
        r'/data/user/0/com.qingdan.qingdan/app_flutter/exports/2026_秋季_学期.ics';
    fake.next = const ExportOutcome.saved(path);
    await tapKey(tester, 'export-run');
    expect(find.textContaining(path), findsOneWidget); // 兜底要求：完整路径可见
    expect(find.byKey(const ValueKey<String>('export-copy')), findsOneWidget);
    await tapKey(tester, 'export-copy'); // 复制到剪贴板不炸即算离线可验的部分
  });

  testWidgets('csv 模式：字节带 UTF-8 BOM 且首行是导入列头',
      (WidgetTester tester) async {
    final _FakeSave fake = _FakeSave();
    await openSheet(tester, width: 1280, saver: fake.call);
    await tapKey(tester, 'export-format-csv');
    await tapKey(tester, 'export-run');
    expect(fake.fileName, '2026_秋季_学期.csv');
    expect(fake.mime, 'text/csv');
    // BOM 断言看**原始字节**：Dart 的 utf8.decode 会把开头的 BOM 吞掉，
    // 拿解码后的字符串 startsWith('\uFEFF') 必红——这正是坑本身。
    expect(fake.bytes!.take(3).toList(), <int>[0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(fake.bytes!),
        startsWith('课程名称,星期,开始节数,结束节数,老师,地点,周数'));
  });

  testWidgets('用户取消：回执说「未写任何文件」，不出现复制按钮',
      (WidgetTester tester) async {
    await openSheet(tester, width: 411, saver: (m, f, b) async => const ExportOutcome.canceled());
    await tapKey(tester, 'export-run');
    expect(find.text('已取消，未写任何文件'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('export-copy')), findsNothing);
  });

  testWidgets('落盘失败：红色「导出失败」回执（不能静默）', (WidgetTester tester) async {
    await openSheet(tester, width: 411, saver: (m, f, b) async => const ExportOutcome.failed());
    await tapKey(tester, 'export-run');
    expect(find.text('导出失败：未能写入文件，请重试'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('export-copy')), findsNothing);
  });
}

/// 记录 saver 收到的三件套，并按 [next] 回一个固定结局（默认=用户取消）。
class _FakeSave {
  String? mime;
  String? fileName;
  Uint8List? bytes;
  ExportOutcome next = const ExportOutcome.canceled();
  Future<ExportOutcome> call(String m, String f, Uint8List b) async {
    mime = m;
    fileName = f;
    bytes = b;
    return next;
  }
}
