import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/shell/placeholder_panes.dart';

import 'tasks_harness.dart';

/// 点通知之后要真的落到那条任务上（M6-C2 交付时留的口子，本次接线）。
///
/// 危害形状：窄屏的详情**不是内嵌面板**，通知回调只设了 `detailTaskId`
/// 就没了下文 —— 用户点了通知，手机打开的是列表页，还得自己找出那条任务，
/// 等于提醒白给。三栏 / 两栏形态详情本来就挂在右侧，不需要推页。
void main() {
  TasksHarness.boot();

  late TasksHarness h;
  setUp(() async {
    h = TasksHarness();
    await h.start();
  });
  tearDown(() => h.stop());

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  /// 全部任务 id（列表页只展示「今天」那一条，两条通知的用例要从库里拿）。
  Future<List<String>> allIds(WidgetTester tester) async {
    final List<Map<String, Object?>>? rows = await io(
        tester, () => h.db.query('tasks', orderBy: 'created_time ASC'));
    return <String>[for (final Map<String, Object?> r in rows!) r['id']! as String];
  }

  testWidgets('窄屏：点通知推全屏详情页，返回后回到列表',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    final String id = h.paneModel.tasks.first.id;
    expect(find.byType(DetailPaneHost), findsNothing, reason: '起初在列表页');

    h.paneModel.openDetailFromNotification(id);
    await tester.pumpAndSettle();

    expect(h.paneModel.detailTaskId, id);
    expect(find.byType(DetailPaneHost), findsOneWidget,
        reason: '详情必须是推出来的全屏页，而不是停在列表页');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DetailPaneHost), findsNothing);
  });

  testWidgets('三栏：同一动作不推页（详情面板本来就在右侧）',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 1280);
    final String id = h.paneModel.tasks.first.id;

    h.paneModel.openDetailFromNotification(id);
    await tester.pumpAndSettle();

    expect(find.byType(DetailPaneHost), findsOneWidget,
        reason: '内嵌的那一个就够，再推一层全屏页等于把三栏壳盖住');
    expect(h.paneModel.detailTaskId, id);
  });

  testWidgets('连点两条通知：两次请求都要被看见（计数器不能被吞）',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    final List<String> ids = await allIds(tester);
    expect(ids.length, greaterThanOrEqualTo(2));

    h.paneModel.openDetailFromNotification(ids[0]);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    h.paneModel.openDetailFromNotification(ids[1]);
    await tester.pumpAndSettle();
    expect(find.byType(DetailPaneHost), findsOneWidget,
        reason: '第二次请求若被当成已处理吞掉，用户点第二条通知就没反应');
    expect(h.paneModel.detailTaskId, ids[1]);
  });
}
