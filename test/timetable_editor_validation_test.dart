import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/timetable_editor.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_theme.dart';

/// M6-A1 节次时间校验的界面回归：**411dp 移动壳与 1280dp 桌面壳各 pump 一次**
/// （总纲铁律 8：双端分发的界面两端各跑一遍，这条是 S4b 用真机事故换来的）。
///
/// 全程只断言 `onSave` 回调，不碰数据库——面板在用户确认前不落库，所以这一层
/// 不需要 `tester.runAsync`，也就不会踩 FakeAsync 下查库挂死的坑。
///
/// 用的数据：07:00 起 / 40 分钟一节 / 课间 5 → 第 i 节 = `420+45(i-1)` 起。
/// 第 12 节是 15:15–15:55；列表限高 240，只有前 5 行会被 layout，所以断言只点
/// 第 2/3 行（第 8、12 行取不到 widget）。
void main() {
  TimeDetail d(int section, int start, int end) => TimeDetail(
      id: 'd$section',
      timetableId: 't1',
      section: section,
      startMinutes: start,
      endMinutes: end);

  List<TimeDetail> day([int count = 12]) => generateTimeDetails(
      timetableId: 't1',
      firstStartMinutes: 420,
      lessonMinutes: 40,
      breakMinutes: 5,
      sectionCount: count);

  final Color overdue = AppColors.light().overdue;

  final List<(String, Size)> shells = <(String, Size)>[
    ('移动 411dp', const Size(411, 900)),
    ('桌面 1280dp', const Size(1280, 1400)),
  ];

  for (final (String label, Size size) in shells) {
    group(label, () {
      late List<TimeDetail> saved;

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

      // 这几个 helper 定义在 testWidgets 之外（拿不到 tester），必须显式传参。
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

      testWidgets('T1 输完 26:00 不按确认键直接点保存：不落库、红字复述原文',
          (tester) async {
        await pump(tester, day());
        await type(tester, 'time-3-start', '26:00');
        // 打字当场就该说话（不等到保存那一下）。
        expect(errorText(tester), contains('第 3 节'));
        expect(errorText(tester), contains('26:00'));
        await tapKey(tester, 'tt-save');
        expect(saved, isEmpty,
            reason: '旧版会拿**没变过的草稿**去保存：框里写着 26:00、库里仍是旧值，'
                '用户看到的就是「点了没反应」');
        expect(find.byKey(const ValueKey<String>('tt-error')), findsOneWidget);
        expect(errorText(tester), contains('26:00'));
        expect(errorText(tester), contains('还有 1 处'));
      });

      testWidgets('T2 那一格进入红框态：helperText 与边框都用 overdue',
          (tester) async {
        await pump(tester, day());
        await type(tester, 'time-3-start', '26:00');
        expect(decOf(tester, 'time-3-start').helperText, '应为 HH:MM');
        expect(borderColor(tester, 'time-3-start'), overdue);
        expect(borderColor(tester, 'time-3-end'), isNot(overdue), reason: '同节另一格不该连坐');
        expect(borderColor(tester, 'time-2-start'), isNot(overdue));
        // 撑高的是 errorText 不是 helperText（列表限高 240，行不能乱跳）。
        expect(decOf(tester, 'time-3-start').errorText, isNull);
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
        await pump(tester, day());
        final double saveTop = tester.getRect(key('tt-save')).top;

        for (final String prefix in <String>['0', '09', '09:', '09:3']) {
          await type(tester, 'time-3-start', prefix);
          expect(find.byKey(const ValueKey<String>('tt-error')), findsNothing,
              reason: '「$prefix」只是还没敲完，不是非法：此刻不该有错误行');
          expect(decOf(tester, 'time-3-start').helperText, isNull,
              reason: 'helperText 一出现就把行撑高，列表跟着抖');
          expect(borderColor(tester, 'time-3-start'), isNot(overdue),
              reason: '中途染红 = 逐键飘红');
          expect(tester.getRect(key('tt-save')).top, closeTo(saveTop, 0.5),
              reason: '错误行与 helperText 都不许把底部按钮行顶下去');
        }

        // 另一半不能丢：敲到一半的文本**照样记在账上**，点保存一定拦得住。
        // （这条改动前后都绿，它是「不许退回静默丢弃输入」的保险，不是新行为的红线。）
        await tapKey(tester, 'tt-save');
        expect(saved, isEmpty, reason: '「09:3」没被静默丢掉，也不该拿旧值去保存');
        expect(errorText(tester), contains('09:3'));
        expect(borderColor(tester, 'time-3-start'), overdue,
            reason: '点保存 = 把只记账的格子第一次染红：拦住要有看得见的原因');

        await type(tester, 'time-3-start', '09:30');
        expect(find.byKey(const ValueKey<String>('tt-error')), findsNothing);
        expect(borderColor(tester, 'time-3-start'), isNot(overdue));
        await tapKey(tester, 'tt-save');
        expect(saved[2].startMinutes, 570);
      });

      // 空串 = 「这一格还没填」，不是非法。改动前它被记成非法原文：红框 + 错误行
      // 都出现（helperText 那条写着「（空）」），保存还被拦住；现在清空就是销账。
      testWidgets('T14 清空成空串算「还没填」：销账、退红，保存走草稿真值',
          (tester) async {
        await pump(tester, day());
        await type(tester, 'time-3-start', '26:00');
        expect(find.byKey(const ValueKey<String>('tt-error')), findsOneWidget);

        await type(tester, 'time-3-start', '');
        expect(find.byKey(const ValueKey<String>('tt-error')), findsNothing,
            reason: '空串不该留下非法原文与错误行');
        expect(decOf(tester, 'time-3-start').helperText, isNull);
        expect(borderColor(tester, 'time-3-start'), isNot(overdue));

        await tapKey(tester, 'tt-save');
        expect(saved, hasLength(12), reason: '没填 = 不改，而不是拦住保存');
        expect(saved[2].startMinutes, 510);
      });

      testWidgets('T3 连点「＋ 添加一节」到 20 节后按钮禁用（不能无限加）',
          (tester) async {
        await pump(tester, <TimeDetail>[d(1, 420, 460)]);
        for (int i = 0; i < 30; i++) {
          if (tester.widget<TextButton>(key('tt-add')).onPressed == null) break;
          await tapKey(tester, 'tt-add');
        }
        expect(tester.widget<TextButton>(key('tt-add')).onPressed, isNull,
            reason: '到第 20 节必须变灰（禁用态要能被断言）');
        await tapKey(tester, 'tt-save');
        expect(saved, hasLength(kMaxSectionsPerDay));
      });

      testWidgets('T4 第 1 节开始改到 23:00：顺移会越界 → 整次拒绝、表格不乱',
          (tester) async {
        await pump(tester, day());
        await type(tester, 'time-1-start', '23:00');
        expect(errorText(tester), contains('顺移后'));
        expect(errorText(tester), contains('超出 00:00–23:59'));
        expect(textOf(tester, 'time-1-start'), '07:00',
            reason: '拒绝改动后必须把文本回读成草稿真值，不能留着新值骗过用户');
        expect(textOf(tester, 'time-2-start'), '07:45', reason: '后续节没被推动');
        await tapKey(tester, 'tt-save');
        expect(saved.first.startMinutes, 420);
        expect(saved[1].startMinutes, 465);
        expect(saved[1].endMinutes, 505);
      });

      testWidgets('T5 错误红字与「保存」同屏：夹在节次列表与按钮行之间',
          (tester) async {
        await pump(tester, day());
        await type(tester, 'time-2-start', '99:99');
        final Rect err = tester.getRect(key('tt-error'));
        final Rect rows = tester.getRect(key('tt-rows'));
        final Rect save = tester.getRect(key('tt-save'));
        final Rect screen = Offset.zero & size;
        expect(screen.contains(err.center), isTrue,
            reason: '红字必须在可视区内（旧版渲染在节次列表上方，手机上看不见）');
        expect(err.top, greaterThanOrEqualTo(rows.bottom - 0.5),
            reason: '红字必须在节次列表**下方**，紧跟用户刚点的那一下');
        expect(err.bottom, lessThanOrEqualTo(save.top + 0.5));
        expect(save.top - err.bottom, lessThan(60), reason: '两者之间不能隔着可滚列表');
      });

      testWidgets('T6 合法输入不等确认键就生效（输完即落草稿）', (tester) async {
        await pump(tester, day());
        await type(tester, 'time-3-start', '09:30');
        await tapKey(tester, 'tt-save');
        expect(saved, hasLength(12));
        expect(saved[2].startMinutes, 570);
        expect(saved[2].endMinutes, 610);
        expect(find.byKey(const ValueKey<String>('tt-error')), findsNothing);
      });

      testWidgets('T7 顺移仍然生效，且确认键重复上报不会推两遍（幂等）',
          (tester) async {
        await pump(tester, day());
        await type(tester, 'time-1-start', '08:00');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(textOf(tester, 'time-2-start'), '08:45');
        expect(textOf(tester, 'time-3-start'), '09:30');
        await tapKey(tester, 'tt-save');
        expect(saved[1].startMinutes, 525);
        expect(saved[2].startMinutes, 570);
      });

      testWidgets('T8 结束时刻不晚于开始：拒绝并说明是哪一节，文本回读真值',
          (tester) async {
        await pump(tester, day());
        await type(tester, 'time-2-end', '06:00');
        expect(errorText(tester), contains('第 2 节'));
        expect(errorText(tester), contains('必须晚于开始时间'));
        expect(textOf(tester, 'time-2-end'), '08:25');
        await tapKey(tester, 'tt-save');
        expect(saved[1].endMinutes, 505, reason: '被拒的 06:00 没进草稿');
      });

      testWidgets('T9 输入闸门：键盘给数字+冒号、最多 5 字符、字母过滤掉',
          (tester) async {
        await pump(tester, day());
        final TextField tf = cell(tester, 'time-3-start');
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

      testWidgets('T10 历史脏数据（24:35）载入即体检：当场标红并拦住保存',
          (tester) async {
        await pump(tester, <TimeDetail>[
          d(1, 420, 460),
          d(2, 465, 505),
          d(3, 1440, 1475),
        ]);
        expect(errorText(tester), contains('历史数据'));
        expect(errorText(tester), contains('第 3 节'));
        expect(borderColor(tester, 'time-3-end'), overdue, reason: '越界那一格当场标红');
        expect(textOf(tester, 'time-3-end'), '24:35', reason: '不自动 clamp：原样显示');
        await tapKey(tester, 'tt-save');
        expect(saved, isEmpty, reason: '脏数据没改正之前不给保存');
      });

      testWidgets('T11 非法文本改回合法：红态与保存拦截一起解除', (tester) async {
        await pump(tester, day());
        await type(tester, 'time-3-start', '26:00');
        expect(decOf(tester, 'time-3-start').helperText, '应为 HH:MM');
        await type(tester, 'time-3-start', '09:30');
        expect(borderColor(tester, 'time-3-start'), isNot(overdue));
        expect(find.byKey(const ValueKey<String>('tt-error')), findsNothing);
        await tapKey(tester, 'tt-save');
        expect(saved, hasLength(12));
        expect(saved[2].startMinutes, 570);
      });

      testWidgets('T12 顺移把别的格子顶回去了：那些格子的非法标记不能留成幽灵',
          (tester) async {
        await pump(tester, day());
        // 第 3 节先写进一个非法文本（红框 + 拦住保存）。
        await type(tester, 'time-3-start', '26:00');
        expect(find.byKey(const ValueKey<String>('tt-error')), findsOneWidget);
        // 再去改第 1 节：第 3 节被顺移覆盖回真值，它的红态必须跟着解除，
        // 而第 3 节那条「26:00」的幽灵标记不能再拦住保存（否则用户找不到哪里不合法）。
        await type(tester, 'time-1-start', '06:00');
        expect(textOf(tester, 'time-3-start'), '07:30');
        await tapKey(tester, 'tt-save');
        expect(saved, hasLength(12), reason: '顺移后草稿合法就该能保存');
        expect(saved[2].startMinutes, 450);
      });
    });
  }
}
