// 同槽循环角标的几何 / 无障碍 / 动画 / 状态归零测试（细化 §2.4，2026-10-19）。
//
// 断言尽量写几何量（尺寸、top、高度），不靠文案碰运气；随宽度分发的界面
// **411 与 1280 各 pump 一遍**。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/features/course/course_cycle_badge.dart';

import 'course_cycle_harness.dart';
import 'dao_test_helper.dart';

void main() {
  ensureSqfliteFfi();

  late CycleEnv env;
  setUp(() async => env = await CycleEnv.open());
  tearDown(() async => env.close());

  /// 周二同一格放两门 1-2 节的课，返回 (默认显示的那条, 另一条)。
  /// 同起始节次按课名排：「大学英语」(U+5927) 在「线性代数」(U+7EBF) 之前。
  Future<(Course, Course)> twoInOneSlot(CycleHarness h,
      {List<int> weeks = const <int>[2]}) async {
    await h.seed();
    final Course linear = await h.add(
        name: '线性代数', location: '逸夫楼201', weeks: weeks);
    final Course english = await h.add(
        name: '大学英语', location: '文成楼125', weeks: weeks);
    return (english, linear);
  }

  for (final double width in <double>[411, 1280]) {
    testWidgets('角标几何：圆底 20dp、点击热区 36dp、贴着块右下角（$width dp）',
        (tester) async {
      final CycleHarness h = CycleHarness(tester, env);
      final (Course english, _) = await twoInOneSlot(h);
      await h.pumpGrid(width: width);

      // 视觉 20dp，但命中框必须铺到 36dp：手机上纯 20dp 图标点不准（真机踩过的坑）。
      expect(tester.getSize(cycleCircle()), const Size(20, 20));
      expect(tester.getSize(cycleHitArea()), const Size(36, 36));
      final Rect block = tester.getRect(blockOf(english.id));
      final Rect hit = tester.getRect(cycleHitArea());
      // 块得吃满整列宽（AnimatedSwitcher 会给子树宽松约束，漏了 StackFit.expand
      // 块就缩成课名那点宽度，角标会飘到块外面）。
      expect(block.width, greaterThanOrEqualTo(60),
          reason: '$width dp 下这一列的课程块不该被压成内容宽');
      expect(hit.right, closeTo(block.right, 1.0), reason: '热区右下角 = 块右下角');
      expect(hit.bottom, closeTo(block.bottom, 1.0));
      expect(hit.left, greaterThanOrEqualTo(block.left),
          reason: '热区整块落在块内，超出部分会被块的裁剪吃掉');
    });

    testWidgets('热区四角（圆底之外）也切得动，不会误开详情（$width dp）',
        (tester) async {
      final CycleHarness h = CycleHarness(tester, env);
      final (Course english, Course linear) = await twoInOneSlot(h);
      await h.pumpGrid(width: width);

      // 点右下角往里 2dp：离圆心超过 10dp，只有把热区做到 36dp 才点得到。
      await tester.tapAt(
          tester.getBottomRight(cycleHitArea()) - const Offset(2, 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump();

      expect(blockOf(linear.id), findsOneWidget, reason: '切到了组内下一条');
      expect(blockOf(english.id), findsNothing);
      expect(find.byType(AlertDialog), findsNothing,
          reason: '这一下落在角标上，不该同时打开详情');
    });
  }

  testWidgets('角标同时给 Tooltip 与 Semantics 文案', (tester) async {
    final CycleHarness h = CycleHarness(tester, env);
    await twoInOneSlot(h);
    await h.pumpGrid(width: 1280);

    // 两门课 → 还有 1 门没在显示。文案由组件自己拼，测试读同一个函数。
    final String text = CourseCycleBadge.labelFor(1);
    expect(find.byTooltip(text), findsOneWidget);
    final List<Semantics> nodes = tester
        .widgetList<Semantics>(find.descendant(
            of: cycleHitArea(), matching: find.byType(Semantics)))
        .toList();
    expect(nodes.map((Semantics s) => s.properties.label), contains(text),
        reason: '无障碍读到的必须是同一句话，不能只有肉眼可见的图标');
    // 光有 label + button 只解决「读得到」，TalkBack 双击下去无动作等于点不动。
    final Semantics labelled =
        nodes.firstWhere((Semantics s) => s.properties.label == text);
    expect(labelled.properties.onTap, isNotNull,
        reason: 'Semantics 得带 tap action，读屏才能真的激活切换');
  });

  testWidgets('切换动画 200ms：中途两条都在树上、旧的不接点击，走完只剩新的（Q5）',
      (tester) async {
    final CycleHarness h = CycleHarness(tester, env);
    final (Course english, Course linear) = await twoInOneSlot(h);
    await h.pumpGrid(width: 1280);

    await tester.tap(cycleHitArea());
    await tester.pump(); // 起帧：AnimatedSwitcher 从这一帧才开始倒 200ms
    await tester.pump(const Duration(milliseconds: 100));
    // 200ms 动画走了一半：正在滑出的旧块与正在滑入的新块同时在树上。
    expect(blockOf(english.id), findsOneWidget);
    expect(blockOf(linear.id), findsOneWidget);
    // 壳里本来就有别的 IgnorePointer（桌面 hover 之类），所以钉的是「恰好多一层」，
    // 不是「有一层」——写成 findsOneWidget 会因为共有的祖先而永远红。
    int guards(Finder f) => find
        .ancestor(of: f, matching: find.byType(IgnorePointer))
        .evaluate()
        .length;
    expect(guards(blockOf(english.id)), guards(blockOf(linear.id)) + 1,
        reason: '退场那一条不能再吃点击，否则这 200ms 里点到它会打开已切走的详情');

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    expect(blockOf(english.id), findsNothing);
    expect(blockOf(linear.id), findsOneWidget);
  });

  testWidgets('跨度不等的组各画各的跨度，不合并成 1-3 的大块', (tester) async {
    final CycleHarness h = CycleHarness(tester, env);
    await h.seed();
    final Course a = await h.add(name: '甲课', start: 1, end: 2);
    final Course b = await h.add(name: '乙课', start: 2, end: 3);
    await h.pumpGrid(width: 1280);

    // 两条重叠在第 2 节 → 传递性合成一组；默认显示起始节次更早的甲课。
    expect(blockOf(a.id), findsOneWidget);
    final ({double top, double height}) rectA =
        env.model.layout.rectFor(1, 2)!;
    final ({double top, double height}) rectB =
        env.model.layout.rectFor(2, 3)!;
    final ({double top, double height}) union =
        env.model.layout.rectFor(1, 3)!;
    // 网格整块在表头下面，屏幕坐标带个固定偏移，所以只比「两块之差」。
    final double beforeTop = tester.getRect(blockOf(a.id)).top;
    expect(tester.getSize(blockOf(a.id)).height, closeTo(rectA.height, 0.5));

    await tapBadge(tester);
    expect(blockOf(b.id), findsOneWidget);
    final Rect after = tester.getRect(blockOf(b.id));
    // 乙课画自己的 2-3 节：位置往下挪一节，高度是两节而不是三节的并集。
    expect(after.height, closeTo(rectB.height, 0.5));
    expect(after.top - beforeTop, closeTo(rectB.top - rectA.top, 0.5),
        reason: '要是画成 1-3 的合并大块，它就会停在甲课的顶部不动');
    expect(after.height, lessThan(union.height),
        reason: '并集跨度（3 节）比乙课自己的 2 节高，画出来就是冒充两门课');
  });

  // 上面那条只看动画**结束后**。这条看中途，钉的是已知取舍（2026-10-19 评审第 3 条）：
  // 组盒子的 Positioned 用「当前选中那条」的 top/height，`_previousBehind` 又是
  // `StackFit.expand`（宽松约束会让块缩成内容宽、角标飘出去，不能换掉），所以
  // 跨度不等的组在切的那 200ms 里，**退场那条会被瞬移并挤进新盒子**。
  // 让它保持自己的 top/height 要绕开 AnimatedSwitcher 自己接管退场布局，
  // 换来的只是半秒过渡里的一个像素差，不值；这里把现状钉住，改坏了会红。
  testWidgets('跨度不等的组：200ms 中途退场那条被瞬移进新盒子（已知取舍）',
      (tester) async {
    final CycleHarness h = CycleHarness(tester, env);
    await h.seed();
    final Course a = await h.add(name: '甲课', start: 1, end: 2); // 自己 88dp
    final Course b = await h.add(name: '乙课', start: 2, end: 2); // 自己 38.5dp
    await h.pumpGrid(width: 1280);
    final ({double top, double height}) rectA =
        env.model.layout.rectFor(1, 2)!;
    final ({double top, double height}) rectB =
        env.model.layout.rectFor(2, 2)!;
    expect(rectA.height, greaterThan(rectB.height + 10),
        reason: '两条跨度不等才有得看');

    await tester.tap(cycleHitArea());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(blockOf(a.id), findsOneWidget);
    expect(blockOf(b.id), findsOneWidget);

    final Rect midA = tester.getRect(blockOf(a.id));
    final Rect midB = tester.getRect(blockOf(b.id));
    expect(midA.height, closeTo(rectB.height, 0.5),
        reason: '甲课在这半秒里用的是乙课的盒子高度（不是自己的 88dp）');
    expect(midA.top, closeTo(midB.top, 0.5),
        reason: '同理，它的顶边已经被挪到乙课那一条的顶上');
  });

  testWidgets('换周之后回到第一条（Q6）', (tester) async {
    final CycleHarness h = CycleHarness(tester, env);
    // 两门课上第 2 周和第 3 周：组身份（成员 id）在两周完全相同，
    // 只有周次变了——这正是签名里必须带 week 的理由。
    final (Course english, Course linear) =
        await twoInOneSlot(h, weeks: <int>[2, 3]);
    await h.pumpGrid(width: 1280);

    await tapBadge(tester);
    expect(blockOf(linear.id), findsOneWidget, reason: '用户切到了第二条');

    await h.goToWeek(3);
    await tester.pumpAndSettle();
    expect(blockOf(english.id), findsOneWidget, reason: '换周不保留索引');

    await h.goToWeek(2);
    await tester.pumpAndSettle();
    expect(blockOf(english.id), findsOneWidget, reason: '翻回来也从第一条开始');
  });

  testWidgets('组里多了一门课（数据重载）之后回到第一条（Q6）', (tester) async {
    final CycleHarness h = CycleHarness(tester, env);
    final (Course english, Course linear) = await twoInOneSlot(h);
    await h.pumpGrid(width: 1280);
    expect(linear.name, '线性代数');

    await tapBadge(tester);
    expect(blockOf(linear.id), findsOneWidget);

    // 同槽再加一门（手工编辑、或同步从另一台设备拉下来都可能造成这件事）。
    final Course newcomer = await h.add(name: 'A课', start: 1, end: 2);
    await h.reload();
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(cycleCounter()).data, '1/3',
        reason: '成员集合变了 → 签名变 → 整表清空，回到第一条');
    expect(blockOf(newcomer.id), findsOneWidget,
        reason: '默认第一条 = 起始节次最早、同节次按课名，「A课」排在中文课名之前');
    expect(blockOf(english.id), findsNothing);
  });

  testWidgets('组内成员改名（组身份没变）之后也回到第一条（Q6 的签名路径）',
      (tester) async {
    final CycleHarness h = CycleHarness(tester, env);
    await h.seed();
    final Course a = await h.add(name: 'A课', start: 1, end: 1);
    final Course b = await h.add(name: 'B课', start: 1, end: 1);
    await h.pumpGrid(width: 1280);

    await tapBadge(tester);
    expect(blockOf(b.id), findsOneWidget, reason: '次序 A、B → 切到第 2 条');

    // 只改课名：成员 id 集合没变（groupKey 也没变），但「起始节次→课名」的次序
    // 变成 B、Z。不清索引的话第 2 条指的是改名后的那门，用户看到的课凭空换了一门。
    await h.rename(a, 'Z课');
    await h.reload();
    await tester.pumpAndSettle();

    expect(blockOf(b.id), findsOneWidget, reason: '签名变了 → 回到第一条 = B课');
    expect(blockOf(a.id), findsNothing);
  });
}
