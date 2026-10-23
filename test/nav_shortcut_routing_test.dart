import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/app.dart';
import 'package:qingdan/features/shell/nav_router.dart';
import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';

import 'tasks_harness.dart';

/// 长按快捷方式（v1.0.6）的路由：路由字符串 → 页签 / 详情 / 快速添加聚焦。
///
/// 危害形状：路由解析错一个字符，用户点「课表」却停在清单页 —— 但没有任何报错，
/// 看起来只是「这个快捷方式没用」。
///
/// 为什么全是 `testWidgets` + `runAsync`：切页签会触发 `TaskPaneModel.load()`
/// 查库，在 FakeAsync 区里它会挂到 `tearDown` 关库之后才抛 `database_closed`
/// （`tasks_harness.dart` 顶部那两条铁律）。
void main() {
  TasksHarness.boot();

  late TasksHarness h;
  late NavRouter router;
  setUp(() async {
    h = TasksHarness();
    await h.start();
    router = NavRouter(
      sidebar: h.sidebar,
      pane: h.paneModel,
      navigatorKey: appNavigatorKey,
    );
  });
  tearDown(() => h.stop());

  /// 在真实异步区执行模型变更，并给切页签触发的查库留出完成时间。
  Future<void> act(WidgetTester tester, void Function() body) async {
    await tester.runAsync(() async {
      body();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  }

  testWidgets('today：从设置页签回到清单·今天', (WidgetTester tester) async {
    await act(tester, () => h.sidebar.selectTab(ShellTab.settings));
    expect(h.sidebar.tab, ShellTab.settings);

    await act(tester, () => router.handle('today'));

    expect(h.sidebar.tab, ShellTab.tasks);
    expect(h.sidebar.selectedId, kSmartToday);
  });

  testWidgets('today：已经停在「今天」时仍能从设置页签切回来',
      (WidgetTester tester) async {
    // selectedId 本来就在 today，`select` 会早退；不加判断的话点「今天」没反应。
    await act(tester, () => h.sidebar.selectTab(ShellTab.settings));
    expect(h.sidebar.selectedId, kSmartToday);

    await act(tester, () => router.handle('today'));

    expect(h.sidebar.tab, ShellTab.tasks);
  });

  testWidgets('course / chaoxing：各落到对应页签', (WidgetTester tester) async {
    await act(tester, () => router.handle('course'));
    expect(h.sidebar.tab, ShellTab.course);

    await act(tester, () => router.handle('chaoxing'));
    expect(h.sidebar.tab, ShellTab.chaoxing);
  });

  testWidgets('task:<id>：切回清单并请求推详情页', (WidgetTester tester) async {
    final String id = h.paneModel.tasks.first.id;
    final int before = h.paneModel.detailPageRequest;

    await act(tester, () => router.handle('task:$id'));

    expect(h.sidebar.tab, ShellTab.tasks);
    expect(h.paneModel.detailTaskId, id);
    expect(h.paneModel.detailPageRequest, before + 1,
        reason: '计数不加，窄屏壳就不会推全屏详情页');
  });

  testWidgets('new_task：切回清单并聚焦快速添加输入框', (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await act(tester, () => h.sidebar.selectTab(ShellTab.settings));
    await tester.pump();
    expect(h.paneModel.quickAddFocus.hasFocus, isFalse);

    await act(tester, () => router.handle('new_task'));
    await tester.pump(); // 切页签
    await tester.pump(); // 帧末的 requestFocus
    await tester.pumpAndSettle();

    expect(h.sidebar.tab, ShellTab.tasks);
    expect(h.paneModel.quickAddFocus.hasFocus, isTrue,
        reason: '快捷方式的卖点就是「点完直接打字」，键盘不出来等于没做');
  });

  testWidgets('设置子页在前台：先弹回壳再切页签（否则看起来点了没反应）',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    appNavigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('设置 · 通用')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('设置 · 通用'), findsOneWidget);

    await act(tester, () => router.handle('new_task'));
    await tester.pumpAndSettle();

    expect(find.text('设置 · 通用'), findsNothing,
        reason: '设置子页盖在上面时只切页签，用户看到的是原页面');
    expect(h.sidebar.tab, ShellTab.tasks);
  });

  testWidgets('未知 / 空路由一律忽略，不抛异常', (WidgetTester tester) async {
    await act(tester, () => h.sidebar.selectTab(ShellTab.course));

    await act(tester, () {
      router.handle(null);
      router.handle('');
      router.handle('unknown');
      router.handle('task:');
    });

    expect(h.sidebar.tab, ShellTab.course);
    expect(h.paneModel.detailTaskId, isNull);
  });
}
