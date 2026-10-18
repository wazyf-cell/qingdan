// M6-A1 节次时间校验的界面回归·值规则与顺移。自 timetable_editor_validation_test.dart
// 拆出：本文件管「添加上限（T3）、越界顺移整次拒绝（T4）、错误行布局位置（T5）、
// 顺移生效与确认键幂等（T7）、结束不晚于开始（T8）、历史脏数据载入即体检（T10）、
// 顺移覆盖后幽灵标记解除（T12）」；输入状态机与红态时机在孪生文件
// timetable_editor_input_state_test.dart。
//
// 共用夹具（双端壳尺寸、pump/打字/读回辅助）见 timetable_editor_harness.dart——
// **411dp 移动壳与 1280dp 桌面壳各 pump 一次**（总纲铁律 8）。全程只断言 `onSave`
// 回调，不碰数据库，所以不需要 `tester.runAsync`。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/time_table.dart';

import 'timetable_editor_harness.dart';

void main() {
  for (final (String label, Size size) in kTimetableShells) {
    group(label, () {
      testWidgets('T3 连点「＋ 添加一节」到 20 节后按钮禁用（不能无限加）',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, <TimeDetail>[ttDetail(1, 420, 460)]);
        for (int i = 0; i < 30; i++) {
          if (tester.widget<TextButton>(probe.key('tt-add')).onPressed == null) break;
          await probe.tapKey(tester, 'tt-add');
        }
        expect(tester.widget<TextButton>(probe.key('tt-add')).onPressed, isNull,
            reason: '到第 20 节必须变灰（禁用态要能被断言）');
        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved, hasLength(kMaxSectionsPerDay));
      });

      testWidgets('T4 第 1 节开始改到 23:00：顺移会越界 → 整次拒绝、表格不乱',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        await probe.type(tester, 'time-1-start', '23:00');
        expect(probe.errorText(tester), contains('顺移后'));
        expect(probe.errorText(tester), contains('超出 00:00–23:59'));
        expect(probe.textOf(tester, 'time-1-start'), '07:00',
            reason: '拒绝改动后必须把文本回读成草稿真值，不能留着新值骗过用户');
        expect(probe.textOf(tester, 'time-2-start'), '07:45', reason: '后续节没被推动');
        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved.first.startMinutes, 420);
        expect(probe.saved[1].startMinutes, 465);
        expect(probe.saved[1].endMinutes, 505);
      });

      testWidgets('T5 错误红字与「保存」同屏：夹在节次列表与按钮行之间',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        await probe.type(tester, 'time-2-start', '99:99');
        final Rect err = tester.getRect(probe.key('tt-error'));
        final Rect rows = tester.getRect(probe.key('tt-rows'));
        final Rect save = tester.getRect(probe.key('tt-save'));
        final Rect screen = Offset.zero & size;
        expect(screen.contains(err.center), isTrue,
            reason: '红字必须在可视区内（旧版渲染在节次列表上方，手机上看不见）');
        expect(err.top, greaterThanOrEqualTo(rows.bottom - 0.5),
            reason: '红字必须在节次列表**下方**，紧跟用户刚点的那一下');
        expect(err.bottom, lessThanOrEqualTo(save.top + 0.5));
        expect(save.top - err.bottom, lessThan(60), reason: '两者之间不能隔着可滚列表');
      });

      testWidgets('T7 顺移仍然生效，且确认键重复上报不会推两遍（幂等）',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        await probe.type(tester, 'time-1-start', '08:00');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(probe.textOf(tester, 'time-2-start'), '08:45');
        expect(probe.textOf(tester, 'time-3-start'), '09:30');
        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved[1].startMinutes, 525);
        expect(probe.saved[2].startMinutes, 570);
      });

      testWidgets('T8 结束时刻不晚于开始：拒绝并说明是哪一节，文本回读真值',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        await probe.type(tester, 'time-2-end', '06:00');
        expect(probe.errorText(tester), contains('第 2 节'));
        expect(probe.errorText(tester), contains('必须晚于开始时间'));
        expect(probe.textOf(tester, 'time-2-end'), '08:25');
        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved[1].endMinutes, 505, reason: '被拒的 06:00 没进草稿');
      });

      testWidgets('T10 历史脏数据（24:35）载入即体检：当场标红并拦住保存',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, <TimeDetail>[
          ttDetail(1, 420, 460),
          ttDetail(2, 465, 505),
          ttDetail(3, 1440, 1475),
        ]);
        expect(probe.errorText(tester), contains('历史数据'));
        expect(probe.errorText(tester), contains('第 3 节'));
        expect(probe.borderColor(tester, 'time-3-end'), probe.overdue, reason: '越界那一格当场标红');
        expect(probe.textOf(tester, 'time-3-end'), '24:35', reason: '不自动 clamp：原样显示');
        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved, isEmpty, reason: '脏数据没改正之前不给保存');
      });

      testWidgets('T12 顺移把别的格子顶回去了：那些格子的非法标记不能留成幽灵',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        // 第 3 节先写进一个非法文本（红框 + 拦住保存）。
        await probe.type(tester, 'time-3-start', '26:00');
        expect(find.byKey(const ValueKey<String>('tt-error')), findsOneWidget);
        // 再去改第 1 节：第 3 节被顺移覆盖回真值，它的红态必须跟着解除，
        // 而第 3 节那条「26:00」的幽灵标记不能再拦住保存（否则用户找不到哪里不合法）。
        await probe.type(tester, 'time-1-start', '06:00');
        expect(probe.textOf(tester, 'time-3-start'), '07:30');
        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved, hasLength(12), reason: '顺移后草稿合法就该能保存');
        expect(probe.saved[2].startMinutes, 450);
      });
    });
  }
}
