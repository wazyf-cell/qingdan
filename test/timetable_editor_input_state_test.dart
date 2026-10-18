// M6-A1 节次时间校验的界面回归·输入状态机与红态时机。自
// timetable_editor_validation_test.dart 拆出：本文件管「打字中途不飘红、点保存才
// 第一次上色、清空即销账、改回合法解除红态、输入闸门 formatter、合法输入输完即
// 生效」这一组行为；值规则（越界顺移、结束晚于开始、历史脏数据、幽灵标记、节数
// 上限、错误行位置）在孪生文件 timetable_editor_value_rules_test.dart。
//
// 共用夹具（双端壳尺寸、pump/打字/读回辅助）见 timetable_editor_harness.dart——
// **411dp 移动壳与 1280dp 桌面壳各 pump 一次**（总纲铁律 8，S4b 真机事故换来的）。
// 全程只断言 `onSave` 回调，不碰数据库，所以不需要 `tester.runAsync`。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'timetable_editor_harness.dart';

void main() {
  for (final (String label, Size size) in kTimetableShells) {
    group(label, () {
      testWidgets('T1 输完 26:00 不按确认键直接点保存：不落库、红字复述原文',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        await probe.type(tester, 'time-3-start', '26:00');
        // 打字当场就该说话（不等到保存那一下）。
        expect(probe.errorText(tester), contains('第 3 节'));
        expect(probe.errorText(tester), contains('26:00'));
        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved, isEmpty,
            reason: '旧版会拿**没变过的草稿**去保存：框里写着 26:00、库里仍是旧值，'
                '用户看到的就是「点了没反应」');
        expect(find.byKey(const ValueKey<String>('tt-error')), findsOneWidget);
        expect(probe.errorText(tester), contains('26:00'));
        expect(probe.errorText(tester), contains('还有 1 处'));
      });

      testWidgets('T2 那一格进入红框态：helperText 与边框都用 overdue',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        await probe.type(tester, 'time-3-start', '26:00');
        expect(probe.decOf(tester, 'time-3-start').helperText, '应为 HH:MM');
        expect(probe.borderColor(tester, 'time-3-start'), probe.overdue);
        expect(probe.borderColor(tester, 'time-3-end'), isNot(probe.overdue), reason: '同节另一格不该连坐');
        expect(probe.borderColor(tester, 'time-2-start'), isNot(probe.overdue));
        // 撑高的是 errorText 不是 helperText（列表限高 240，行不能乱跳）。
        expect(probe.decOf(tester, 'time-3-start').errorText, isNull);
      });

      // T1 钉住「点保存一定拦得住」；这一条钉住它的另一半：**拦得住 ≠ 一路报警**。
      // 旧实现每次 onChanged 里「解析不过」既记账又立刻上色（invalid 就是解析不过），
      // 所以敲 `0` 的那一帧下面这四条全红：
      //  - `tt-error` 存在（`_markInvalid` 无条件设 `_error`）；
      //  - `helperText == '应为 HH:MM'`（旧版 invalid=true 直接给）；
      //  - `enabledBorder` 颜色 == overdue；
      //  - `tt-save` 的 top 被错误行往下顶 —— 就是用户报的「手机上打字时列表抖」。
      testWidgets('T13 逐键 0→09→09:→09:3 全程中性：不红、不顶行；点保存才第一次上色',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        final double saveTop = tester.getRect(probe.key('tt-save')).top;

        for (final String prefix in <String>['0', '09', '09:', '09:3']) {
          await probe.type(tester, 'time-3-start', prefix);
          expect(find.byKey(const ValueKey<String>('tt-error')), findsNothing,
              reason: '「$prefix」只是还没敲完，不是非法：此刻不该有错误行');
          expect(probe.decOf(tester, 'time-3-start').helperText, isNull,
              reason: 'helperText 一出现就把行撑高，列表跟着抖');
          expect(probe.borderColor(tester, 'time-3-start'), isNot(probe.overdue),
              reason: '中途染红 = 逐键飘红');
          expect(tester.getRect(probe.key('tt-save')).top, closeTo(saveTop, 0.5),
              reason: '错误行与 helperText 都不许把底部按钮行顶下去');
        }

        // 另一半不能丢：敲到一半的文本**照样记在账上**，点保存一定拦得住。
        // （这条改动前后都绿，它是「不许退回静默丢弃输入」的保险，不是新行为的红线。）
        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved, isEmpty, reason: '「09:3」没被静默丢掉，也不该拿旧值去保存');
        expect(probe.errorText(tester), contains('09:3'));
        expect(probe.borderColor(tester, 'time-3-start'), probe.overdue,
            reason: '点保存 = 把只记账的格子第一次染红：拦住要有看得见的原因');

        await probe.type(tester, 'time-3-start', '09:30');
        expect(find.byKey(const ValueKey<String>('tt-error')), findsNothing);
        expect(probe.borderColor(tester, 'time-3-start'), isNot(probe.overdue));
        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved[2].startMinutes, 570);
      });

      // 空串 = 「这一格还没填」，不是非法。改动前它被记成非法原文：红框 + 错误行
      // 都出现（helperText 那条写着「（空）」），保存还被拦住；现在清空就是销账。
      testWidgets('T14 清空成空串算「还没填」：销账、退红，保存走草稿真值',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        await probe.type(tester, 'time-3-start', '26:00');
        expect(find.byKey(const ValueKey<String>('tt-error')), findsOneWidget);

        await probe.type(tester, 'time-3-start', '');
        expect(find.byKey(const ValueKey<String>('tt-error')), findsNothing,
            reason: '空串不该留下非法原文与错误行');
        expect(probe.decOf(tester, 'time-3-start').helperText, isNull);
        expect(probe.borderColor(tester, 'time-3-start'), isNot(probe.overdue));

        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved, hasLength(12), reason: '没填 = 不改，而不是拦住保存');
        expect(probe.saved[2].startMinutes, 510);
      });

      testWidgets('T6 合法输入不等确认键就生效（输完即落草稿）', (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        await probe.type(tester, 'time-3-start', '09:30');
        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved, hasLength(12));
        expect(probe.saved[2].startMinutes, 570);
        expect(probe.saved[2].endMinutes, 610);
        expect(find.byKey(const ValueKey<String>('tt-error')), findsNothing);
      });

      testWidgets('T9 输入闸门：键盘给数字+冒号、最多 5 字符、字母过滤掉',
          (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        final TextField tf = probe.cell(tester, 'time-3-start');
        expect(tf.keyboardType, TextInputType.datetime);
        expect(tf.maxLength, 5);
        expect(tf.inputFormatters, hasLength(1));
        final TextEditingValue filtered = tf.inputFormatters!.first
            .formatEditUpdate(
              const TextEditingValue(
                text: '',
                selection: TextSelection.collapsed(offset: 0),
                composing: TextRange.empty,
              ),
              const TextEditingValue(
                text: 'ab26:00c',
                selection: TextSelection.collapsed(offset: 8),
                composing: TextRange.empty,
              ),
            );
        expect(filtered.text, '26:00', reason: '字母被滤掉，冒号可以输进来');
      });

      testWidgets('T11 非法文本改回合法：红态与保存拦截一起解除', (tester) async {
        final TimetableEditorProbe probe = TimetableEditorProbe(size);
        await probe.pump(tester, ttDay());
        await probe.type(tester, 'time-3-start', '26:00');
        expect(probe.decOf(tester, 'time-3-start').helperText, '应为 HH:MM');
        await probe.type(tester, 'time-3-start', '09:30');
        expect(probe.borderColor(tester, 'time-3-start'), isNot(probe.overdue));
        expect(find.byKey(const ValueKey<String>('tt-error')), findsNothing);
        await probe.tapKey(tester, 'tt-save');
        expect(probe.saved, hasLength(12));
        expect(probe.saved[2].startMinutes, 570);
      });
    });
  }
}
