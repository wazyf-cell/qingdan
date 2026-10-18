import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'tasks_harness.dart';

/// 清单页（M5-S2）窄屏形态回归测试。环境（真库 + provider 装配 + `runAsync` 规矩）
/// 在 `tasks_harness.dart`，快捷抽屉的用例在 `quick_compose_test.dart`。
///
/// 覆盖定案第 4 条（顶部视图 chips + 左上清单半屏面板 + 右上 ⋮ 回收站）与
/// 第 7 条（「今天」页的学习通到期提示条），并按 S4b 教训在 1280dp 各跑一遍，
/// 确认桌面三栏没被牵连。
void main() {
  TasksHarness.boot();

  late TasksHarness h;
  setUp(() async {
    h = TasksHarness();
    await h.start();
  });
  tearDown(() => h.stop());

  testWidgets('视图 chips：选中态跟随 selectedId，点「最近 7 天」即切视图',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);

    expect(h.chipOf(tester, kSmartToday).selected, isTrue);
    expect(h.chipOf(tester, kSmartNext7).selected, isFalse);
    // 计数从抽屉搬进 chips：种的那条「今天」到期任务要数进来
    //（「交开题」没有到期日，所以是 1 而不是 2）。
    expect(h.textOf(tester, 'chip:today'), '今天 1');

    await h.tapIo(tester, h.key('chip:next7'));

    expect(h.sidebar.selectedId, kSmartNext7);
    expect(h.chipOf(tester, kSmartNext7).selected, isTrue);
    expect(h.chipOf(tester, kSmartToday).selected, isFalse);
  });

  testWidgets('左上「清单 ▾」开半屏面板：切换清单，选完自动收起',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await h.openSheet(tester);

    // 面板里只有用户清单：库里**没有**收集箱 seed 行（收集箱 = list_id IS NULL），
    // 所以侧栏那套「收集箱（内置）」在真机上本来就不渲染，别把它当回归点。
    expect(find.text('毕设'), findsOneWidget);
    expect(find.text('我的清单'), findsOneWidget);

    await h.tapIo(tester, find.text('毕设'));

    expect(h.sidebar.selectedId, h.gradId);
    // 面板必须自己关掉：M3 收口时抽屉就是栽在「选完不收起」，同一个坑不重踩。
    expect(find.text('我的清单'), findsNothing);
  });

  testWidgets('面板内重命名：写库后侧栏换新名', (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await h.openSheet(tester);

    await h.tapIo(tester, h.key('listMenu:${h.gradId}'));
    await h.tapIo(tester, find.text('重命名'));
    // 只认对话框里的那个输入框：页面上方还有快速添加的 TextField。
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

  testWidgets('右上 ⋮ 进回收站：工具行与顶栏标题都在',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);

    await h.tapIo(tester, find.byIcon(Icons.more_vert));
    expect(h.key('menuTrash'), findsOneWidget);

    await h.tapIo(tester, h.key('menuTrash'));

    expect(h.sidebar.selectedId, kTrash);
    expect(find.text('清空回收站'), findsOneWidget);
    expect(h.textOf(tester, 'topBarTitle'), '回收站');
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
    expect(h.key('listSwitcher'), findsNothing);
    expect(h.key('chip:today'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // 快捷抽屉是窄屏专属：桌面用顶部输入框 + 详情面板。
    expect(h.key('add-task'), findsNothing);
  });
}
