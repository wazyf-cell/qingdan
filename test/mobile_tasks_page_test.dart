import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'tasks_harness.dart';

/// 清单页（M5-S2，M6-A2 改版）窄屏形态回归测试。环境（真库 + provider 装配 +
/// `runAsync` 规矩）在 `tasks_harness.dart`，快捷抽屉的用例在 `quick_compose_test.dart`。
///
/// 覆盖定案第 4 条（视图 chips + 清单半屏面板 + 回收站入口）、第 7 条（「今天」页的
/// 学习通到期提示条）与 M6-A2（顶部三个图标按钮 / 面板首行「全部清单」/ 排序挪到
/// chips 行尾），并按 S4b 教训在 1280dp 各跑一遍，确认桌面三栏没被牵连。
void main() {
  TasksHarness.boot();

  late TasksHarness h;
  setUp(() async {
    h = TasksHarness();
    await h.start();
  });
  tearDown(() => h.stop());

  testWidgets('视图 chips：选中态跟随 selectedId，智能视图下没有排序按钮',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);

    expect(h.chipOf(tester, kSmartToday).selected, isTrue);
    expect(h.chipOf(tester, kSmartNext7).selected, isFalse);
    // 计数从抽屉搬进 chips：种的那条「今天」到期任务要数进来
    //（「交开题」没有到期日，所以是 1 而不是 2）。
    expect(h.textOf(tester, 'chip:today'), '今天 1');
    // M6-A2：排序只对用户清单有意义，智能视图下整颗按钮不渲染。
    expect(h.key('btn-sort'), findsNothing);

    await h.tapIo(tester, h.key('chip:next7'));

    expect(h.sidebar.selectedId, kSmartNext7);
    expect(h.chipOf(tester, kSmartNext7).selected, isTrue);
    expect(h.chipOf(tester, kSmartToday).selected, isFalse);
  });

  testWidgets('顶部三个图标按钮：清单列表 / 添加清单 / 回收站，⋮ 已下线',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);

    expect(tester.widget<IconButton>(h.key('btn-lists')).tooltip, '清单列表');
    expect(tester.widget<IconButton>(h.key('btn-new-list')).tooltip, '添加清单');
    expect(tester.widget<IconButton>(h.key('btn-trash')).tooltip, '回收站');
    // 旧入口必须彻底消失：⋮ 与「清单」文本按钮都不再渲染（面板没开）。
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(h.key('menuTrash'), findsNothing);

    // 几何：三颗按钮同排、自左向右、不越出 411dp；顶栏标题仍是单行（两行≈48dp）。
    final Rect lists = tester.getRect(h.key('btn-lists'));
    final Rect add = tester.getRect(h.key('btn-new-list'));
    final Rect trash = tester.getRect(h.key('btn-trash'));
    expect((lists.top - add.top).abs(), lessThan(0.5));
    expect((add.top - trash.top).abs(), lessThan(0.5));
    expect(lists.left, lessThan(add.left));
    expect(add.left, lessThan(trash.left));
    expect(trash.right, lessThanOrEqualTo(411));
    expect(
        tester.getRect(find.byKey(const ValueKey<String>('topBarTitle'))).height,
        lessThan(40));
  });

  testWidgets('面板首行「全部清单」：回到所有清单的待办，chips 落到「所有」',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await h.openSheet(tester);

    expect(h.key('list-all'), findsOneWidget);
    expect(find.text('所有清单的待办'), findsOneWidget);
    // 「全部清单」必须在用户清单行**上方**（定案：固定首行）。
    expect(tester.getRect(h.key('list-all')).top,
        lessThan(tester.getRect(find.text('毕设')).top));

    await h.tapIo(tester, h.key('list-all'));

    expect(find.text('我的清单'), findsNothing);
    expect(h.sidebar.selectedId, kSmartAll);
    expect(h.chipOf(tester, kSmartAll).selected, isTrue);
    expect(h.key('btn-sort'), findsNothing);
    // 两个来源都在：收集箱的「买牛奶」+「毕设」的「交开题」。
    expect(find.text('买牛奶'), findsOneWidget);
    expect(find.text('交开题'), findsOneWidget);
  });

  testWidgets('面板内点清单：收起、只看该清单待办；四枚 chip 都不亮（不假亮「所有」）',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await h.openSheet(tester);

    expect(find.text('毕设'), findsOneWidget);
    expect(find.text('我的清单'), findsOneWidget);

    await h.tapIo(tester, find.text('毕设'));

    expect(h.sidebar.selectedId, h.gradId);
    // 面板必须自己关掉：M3 收口时抽屉就是栽在「选完不收起」，同一个坑不重踩。
    expect(find.text('我的清单'), findsNothing);
    // selectedId 只有一个槽，装了清单就装不了时间视图。原先这里断言「所有」chip
    // 亮着，是渲染技巧糊出来的假亮：点这个已经亮着的 chip 会让内容从「仅毕设(含已
    // 完成)」暴变成「所有清单未完成」、它挂的又是全局未完成计数、同屏清单面板里选
    // 中的还是「毕设」行 —— 三处自相矛盾。改这条期望不是削弱断言：原来它钉的就是
    // 一个会说谎的状态。现在如实：四枚都不亮。
    for (final String v in <String>[
      kSmartToday, kSmartNext7, kSmartAll, kSmartCompleted,
    ]) {
      expect(h.chipOf(tester, v).selected, isFalse,
          reason: '用户清单视图下 chip:$v 不该亮（没有真值支撑）');
    }
    expect(find.text('交开题'), findsOneWidget);
    expect(find.text('买牛奶'), findsNothing);
    expect(h.key('btn-sort'), findsOneWidget);
  });

  testWidgets('顶栏「＋」新建清单：与面板添加按钮同一条实现（对话框 → 写库 → 侧栏刷新）',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);

    await h.tapIo(tester, h.key('btn-new-list'));

    // 只认对话框里的那个输入框：页面上方还有快速添加的 TextField。
    final Finder field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    expect(field, findsOneWidget);
    expect(find.widgetWithText(TextButton, '创建'), findsOneWidget);

    await tester.enterText(field, '竞赛');
    await h.tapIo(tester, find.widgetWithText(TextButton, '创建'));

    expect(h.sidebar.lists.map((TaskList l) => l.name), contains('竞赛'));
    // 读库确认（不只是内存模型）：新清单真的落进了 `lists` 表。
    final List<TaskList>? rows =
        await h.io(tester, () => h.listUseCase.findAll());
    expect(rows!.map((TaskList l) => l.name), contains('竞赛'));
  });

  testWidgets('面板内重命名：写库后侧栏换新名', (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await h.openSheet(tester);

    await h.tapIo(tester, h.key('listMenu:${h.gradId}'));
    await h.tapIo(tester, find.text('重命名'));
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        '竞赛');
    await h.tapIo(tester, find.widgetWithText(TextButton, '保存'));

    expect(h.sidebar.lists.map((TaskList l) => l.name), contains('竞赛'));
    expect(h.sidebar.lists.map((TaskList l) => l.name), isNot(contains('毕设')));
  });

  testWidgets('面板内删除当前清单：视图落回「今天」，任务落回收集箱',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);

    await h.openSheet(tester);
    await h.tapIo(tester, find.text('毕设'));
    expect(h.sidebar.selectedId, h.gradId);

    await h.openSheet(tester);
    await h.tapIo(tester, h.key('listMenu:${h.gradId}'));
    await h.tapIo(tester, find.text('删除'));
    await h.tapIo(tester, find.widgetWithText(TextButton, '删除'));

    expect(h.sidebar.lists.map((TaskList l) => l.name), isNot(contains('毕设')));
    expect(h.sidebar.selectedId, kSmartToday);
    final List<Task>? active =
        await h.io(tester, () => h.taskUseCase.findAllActive());
    final Task survivor = active!.firstWhere((Task t) => t.title == '交开题');
    expect(survivor.listId, isNull, reason: '任务应落回收集箱（迁移 v2 语义）');
  });

  testWidgets('顶部垃圾桶按钮进回收站：面板与标题切换、FAB 与排序按钮都退场',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);

    await h.tapIo(tester, h.key('btn-trash'));

    expect(h.sidebar.selectedId, kTrash);
    expect(find.text('清空回收站'), findsOneWidget);
    expect(h.textOf(tester, 'topBarTitle'), '回收站');
    expect(h.key('btn-sort'), findsNothing);
    expect(h.key('add-task'), findsNothing);
  });

  testWidgets('chips 行尾排序按钮：四档菜单原样搬来，选「按标题」落到模型',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await h.openSheet(tester);
    await h.tapIo(tester, find.text('毕设'));
    expect(h.key('btn-sort'), findsOneWidget);

    await h.tapIo(tester, h.key('btn-sort'));
    expect(find.text('手动排序'), findsOneWidget);
    expect(find.text('按到期时间'), findsOneWidget);
    expect(find.text('按优先级'), findsOneWidget);
    expect(find.text('按标题'), findsOneWidget);

    // 几何钉住「菜单宽度」：`PopupMenuButton.constraints` 管的是**弹层**不是按钮，
    // 曾被人写成 tightFor(40,40) → 整张菜单 40dp 宽、中文折成一字一行，第四项
    // 既看不见也点不到（411dp 实测 menuItem rect 宽 40、高 60~100）。
    for (int i = 0; i < 4; i++) {
      final Rect item =
          tester.getRect(find.byType(PopupMenuItem<TaskSortMode>).at(i));
      expect(item.width, greaterThanOrEqualTo(56),
          reason: '菜单至少要有 Material 的 2×56 最小宽，否则文案会被折成竖排');
      expect(item.top, greaterThanOrEqualTo(0));
      expect(item.bottom, lessThanOrEqualTo(900),
          reason: '四项都得落在屏幕内，手机上不能有不 reachable 的档位');
    }

    await h.tapIo(tester, find.text('按标题'));

    expect(h.paneModel.sortMode, TaskSortMode.title);
    expect(find.text('交开题'), findsOneWidget);
  });

  testWidgets('「今天」页的学习通到期提示条：只数 24 小时内的待办，点了跳页签',
      (WidgetTester tester) async {
    final ChaoxingModel chaoxing = h.chaoxing;
    final DateTime now = DateTime.now();
    chaoxing.fetchedAt = now;
    chaoxing.now = now;
    chaoxing.tasks = <ChaoxingTask>[
      ChaoxingTask(
          id: 'a1',
          courseId: 'c1',
          courseName: '数据结构',
          title: '第一章作业',
          kind: '作业',
          ongoing: true,
          serverStatus: '未提交',
          dueAt: now.add(const Duration(hours: 6))),
      ChaoxingTask(
          id: 'a2',
          courseId: 'c1',
          courseName: '数据结构',
          title: '第二章作业',
          kind: '作业',
          ongoing: true,
          serverStatus: '未提交',
          dueAt: now.add(const Duration(days: 3))),
    ];
    await h.pumpAtWidth(tester, 411);

    final Finder banner = find.text('学习通有 1 条 24 小时内到期');
    expect(banner, findsOneWidget);

    // 切出「今天」提示条就该消失：它说的是今天的到期压力，不是全局横幅。
    await h.tapIo(tester, h.key('chip:next7'));
    expect(banner, findsNothing);

    await h.tapIo(tester, h.key('chip:today'));
    expect(banner, findsOneWidget);
    await h.tapIo(tester, banner);

    expect(h.sidebar.tab, ShellTab.chaoxing);
    expect(h.sidebar.selectedId, kChaoxing);
  });

  testWidgets('窄屏不再自绘标题行与手动同步图标（同步入口归顶栏状态槽）',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);

    expect(h.key('paneTitle'), findsNothing);
    // `_ManualSyncButton` 的两个图标：清单页自带页头后不该再出现，
    // 否则同步入口在 56dp 顶栏与页内各来一遍。
    expect(find.byIcon(Icons.sync_outlined), findsNothing);
    expect(find.byIcon(Icons.sync), findsNothing);
  });

  testWidgets('1280dp 桌面三栏不受影响：标题行仍在列表区，无清单页页头',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 1280);

    expect(h.key('paneTitle'), findsOneWidget);
    expect(h.textOf(tester, 'paneTitle'), '今天');
    // 三按钮与「全部清单」首行都是窄屏专属，桌面一套组件没被牵连。
    expect(h.key('btn-lists'), findsNothing);
    expect(h.key('btn-new-list'), findsNothing);
    expect(h.key('btn-trash'), findsNothing);
    expect(h.key('btn-sort'), findsNothing);
    expect(h.key('list-all'), findsNothing);
    expect(h.key('chip:today'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // 快捷抽屉是窄屏专属：桌面用顶部输入框 + 详情面板。
    expect(h.key('add-task'), findsNothing);
  });
}
