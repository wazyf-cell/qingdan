// 同槽「单块 + 循环角标」的交互测试（细化 §2.4，2026-10-19 改版）。
//
// 界面随宽度分发 → **411 与 1280 各 pump 一遍**（S4b 的教训：只 pump 1280 的
// 桌面壳，移动端布局缺陷会整批溜过去）。几何量断言在 course_cycle_geom_test.dart。
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';

import 'course_cycle_harness.dart';
import 'dao_test_helper.dart';

void main() {
  ensureSqfliteFfi();

  late CycleEnv env;
  setUp(() async => env = await CycleEnv.open());
  tearDown(() async => env.close());

  for (final double width in <double>[411, 1280]) {
    testWidgets('单门课不挂角标、不显示计数（$width dp，Q2）', (tester) async {
      final CycleHarness h = CycleHarness(tester, env);
      await h.seed();
      final Course solo = await h.add(name: '高等数学', location: '逸夫楼201');
      await h.pumpGrid(width: width);

      expect(blockOf(solo.id), findsOneWidget);
      expect(cycleIcon(), findsNothing, reason: '一门课没有可切的对象');
      expect(cycleCounter(), findsNothing);
    });

    testWidgets('两门课：只显示一条 + 角标，点角标切到另一门并循环回来（$width dp，Q3）',
        (tester) async {
      final CycleHarness h = CycleHarness(tester, env);
      await h.seed();
      final Course linear = await h.add(name: '线性代数', location: '逸夫楼201');
      final Course english =
          await h.add(name: '大学英语', location: '文成楼125');
      await h.pumpGrid(width: width);

      // 同起始节次按课名排 → 「大学英语」在前（Q6，与旧堆叠的先后次序一致）。
      expect(blockOf(english.id), findsOneWidget);
      expect(
          blockOf(linear.id), findsNothing,
          reason: '组内其余条隐藏：不再把跨度均分成两条矮块');
      expect(cycleIcon(), findsOneWidget);
      // 总数 == 2 时 ⇄ 本身已经说明只有一条备选，不再显示「1/2」（Q4）。
      expect(cycleCounter(), findsNothing);

      await tapBadge(tester);
      expect(blockOf(linear.id), findsOneWidget);
      expect(blockOf(english.id), findsNothing);

      await tapBadge(tester);
      expect(blockOf(english.id), findsOneWidget, reason: '切到底是循环，不是撞墙');
    });

    testWidgets('三门课：块内右上显示 1/3，连点走一圈（$width dp，Q4）', (tester) async {
      final CycleHarness h = CycleHarness(tester, env);
      await h.seed();
      final Course b = await h.add(name: 'B课', start: 1, end: 1);
      final Course c = await h.add(name: 'C课', start: 1, end: 1);
      final Course a = await h.add(name: 'A课', start: 1, end: 1);
      await h.pumpGrid(width: width);

      expect(find.text('1/3'), findsOneWidget);
      expect(blockOf(a.id), findsOneWidget);

      await tapBadge(tester);
      expect(find.text('2/3'), findsOneWidget);
      expect(blockOf(b.id), findsOneWidget);

      await tapBadge(tester);
      expect(find.text('3/3'), findsOneWidget);
      expect(blockOf(c.id), findsOneWidget);

      await tapBadge(tester);
      expect(find.text('1/3'), findsOneWidget);
      expect(blockOf(a.id), findsOneWidget);
      // 三门挤同一节也**不降级**：还是完整一块 + 角标，课名不再被压成首二字。
      expect(find.text('A课'), findsOneWidget);
    });
  }

  for (final double width in <double>[411, 1280]) {
    // 原来只 pump 1280：窄屏走的是另一套分发（移动端这里弹底部抽屉、桌面弹
    // AlertDialog），漏 pump 就等于没测（S4b 的教训）。
    testWidgets('点块本体 = 打开当前显示那一门的详情（$width dp，Q3，行为不变）',
        (tester) async {
      final CycleHarness h = CycleHarness(tester, env);
      await h.seed();
      await h.add(name: '线性代数', location: '逸夫楼201');
      final Course english = await h.add(name: '大学英语', location: '文成楼125');
      await h.pumpGrid(width: width);

      expect(blockOf(english.id), findsOneWidget);
      // 点块的中心：1-2 节的块高 88dp，中心在 y=44，而角标只吃底部 36dp
      // （y≥52），所以这一下必然落在块本体上，不是角标。
      await tester.tap(blockOf(english.id));
      await tester.pumpAndSettle();
      // 详情弹层里带「地点：…」前缀，块里只有裸地点名，所以这句只可能来自弹层。
      expect(find.textContaining('地点：文成楼125'), findsOneWidget);
      expect(find.textContaining('地点：逸夫楼201'), findsNothing,
          reason: '打开的是当前显示的那一门，不是组里另一门');
    });
  }

  testWidgets('周次不重叠的两门课本周不该有角标（Q2）', (tester) async {
    final CycleHarness h = CycleHarness(tester, env);
    await h.seed(totalWeeks: 16);
    await h.add(name: '前八周', weeks: List<int>.generate(8, (int i) => i + 1));
    await h.add(name: '后八周', weeks: List<int>.generate(8, (int i) => i + 9));
    await h.pumpGrid(width: 1280); // 今天是第 2 周的周一

    expect(find.text('前八周'), findsOneWidget);
    expect(cycleIcon(), findsNothing,
        reason: '另一门要到第 9 周才上，本周这一格只有一门课');

    await h.goToWeek(9);
    await tester.pumpAndSettle();
    expect(find.text('后八周'), findsOneWidget);
    expect(cycleIcon(), findsNothing, reason: '同一格换到第 9 周也只有一门');
  });

  testWidgets('组里画不出来的成员不进循环、不虚增角标', (tester) async {
    final CycleHarness h = CycleHarness(tester, env);
    await h.seed(); // 作息表只排到第 3 节
    final Course ok = await h.add(name: '正常课', start: 1, end: 2);
    final Course bad = await h.add(name: '越界课', start: 2, end: 5);
    await h.pumpGrid(width: 1280);

    expect(blockOf(ok.id), findsOneWidget);
    expect(blockOf(bad.id), findsNothing, reason: '第 4-5 节没排，进「未排时间」区');
    expect(find.text('未排时间（1）'), findsOneWidget);
    expect(cycleIcon(), findsNothing,
        reason: '能画的只剩一条，切过去会是一片空白');
  });
}
