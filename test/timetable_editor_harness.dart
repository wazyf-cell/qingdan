// 作息编辑面板校验测试的共用夹具（自 timetable_editor_validation_test.dart 拆出；
// 非 `_test` 文件，flutter test 不直接执行）。
//
// M6-A1 节次时间校验的界面回归：**411dp 移动壳与 1280dp 桌面壳各 pump 一次**
// （总纲铁律 8：双端分发的界面两端各跑一遍，这条是 S4b 用真机事故换来的）。
// 两份分册：
//  - timetable_editor_input_state_test.dart —— 打字状态机与红态时机（T1/T2/T6/T9/T11/T13/T14）
//  - timetable_editor_value_rules_test.dart —— 值规则、顺移与布局（T3/T4/T5/T7/T8/T10/T12）
//
// 全程只断言 `onSave` 回调，不碰数据库——面板在用户确认前不落库，所以这一层
// 不需要 `tester.runAsync`，也就不会踩 FakeAsync 下查库挂死的坑。
//
// 用的数据：07:00 起 / 40 分钟一节 / 课间 5 → 第 i 节 = `420+45(i-1)` 起。
// 第 12 节是 15:15–15:55；列表限高 240，只有前 5 行会被 layout，所以断言只点
// 第 2/3 行（第 8、12 行取不到 widget）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/timetable_editor.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_theme.dart';

TimeDetail ttDetail(int section, int start, int end) => TimeDetail(
    id: 'd$section',
    timetableId: 't1',
    section: section,
    startMinutes: start,
    endMinutes: end);

List<TimeDetail> ttDay([int count = 12]) => generateTimeDetails(
    timetableId: 't1',
    firstStartMinutes: 420,
    lessonMinutes: 40,
    breakMinutes: 5,
    sectionCount: count);

/// 双端壳尺寸（铁律 8 的落点：每条用例在两种视口各跑一遍）。
const List<(String, Size)> kTimetableShells = <(String, Size)>[
  ('移动 411dp', Size(411, 900)),
  ('桌面 1280dp', Size(1280, 1400)),
];

/// 一轮面板探测：把面板 pump 进指定壳、跑打字/点击/读回辅助，并接收 onSave 草稿。
class TimetableEditorProbe {
  TimetableEditorProbe(this.size);

  final Size size;
  final Color overdue = AppColors.light().overdue;
  List<TimeDetail> saved = <TimeDetail>[];

  Finder key(String k) => find.byKey(ValueKey<String>(k));

  Future<void> pump(WidgetTester tester, List<TimeDetail> initial) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    saved = <TimeDetail>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TimetableEditPanel(
            initialDetails: initial,
            isMobile: size.width < 720,
            onSave: (List<TimeDetail> draft) =>
                saved = List<TimeDetail>.of(draft),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// 只打字、**不按键盘确认键**：这正是旧代码完全接不住的那条路径。
  Future<void> type(WidgetTester tester, String k, String text) async {
    await tester.enterText(key(k), text);
    await tester.pump();
  }

  /// 全部用单帧 pump，不用 pumpAndSettle / ensureVisible：格子一旦拿到焦点，
  /// 光标闪烁会让 pumpAndSettle 永远等不到静止帧（本仓库已踩过一次挂死）。
  /// 面板在这两种视口下都不需要滚动，所以不 ensureVisible 也点得到。
  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.tap(key(k));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // 这些 helper 定义在 testWidgets 之外（拿不到 tester），必须显式传参。
  TextField cell(WidgetTester tester, String k) =>
      tester.widget<TextField>(key(k));

  String textOf(WidgetTester tester, String k) =>
      cell(tester, k).controller!.text;

  String errorText(WidgetTester tester) =>
      (tester.widget<Text>(key('tt-error')).data)!;

  InputDecoration decOf(WidgetTester tester, String k) =>
      cell(tester, k).decoration!;

  Color borderColor(WidgetTester tester, String k) =>
      (decOf(tester, k).enabledBorder! as OutlineInputBorder).borderSide.color;
}
