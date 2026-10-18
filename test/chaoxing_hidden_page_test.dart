import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/chaoxing/chaoxing_hidden_entry.dart';
import 'package:qingdan/features/chaoxing/chaoxing_keys.dart';
import 'package:qingdan/features/chaoxing/chaoxing_prefs.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_harness.dart';

/// M6B §B6：隐藏列表是整页，能看、能恢复、能清理「已失效」。
/// 旧代码只存 `courseId|id` 字符串、页面根本不存在，所以这几条全都要红。
void main() {
  List<ChaoxingHiddenEntry> entries({bool deadSecond = false}) =>
      <ChaoxingHiddenEntry>[
        ChaoxingHiddenEntry(
            key: 'c1|1',
            courseName: '课程甲',
            title: '第一次作业',
            dueMs: kCxNow.add(const Duration(hours: 6)).millisecondsSinceEpoch,
            hiddenAtMs: kCxNow.subtract(const Duration(days: 1)).millisecondsSinceEpoch),
        ChaoxingHiddenEntry(
            key: 'c1|2',
            courseName: '课程乙',
            title: '第二次作业',
            dueMs: kCxNow.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
            hiddenAtMs: kCxNow.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
            dead: deadSecond),
      ];

  Map<String, Object> seed({bool deadSecond = false}) => <String, Object>{
        ChaoxingPrefs.kHiddenKey: <String>['c1|1', 'c1|2'],
        ChaoxingPrefs.kHiddenMetaKey:
            ChaoxingHiddenEntry.encode(entries(deadSecond: deadSecond)),
      };

  List<ChaoxingTask> tasks() => <ChaoxingTask>[
        cxHomework('1'),
        cxHomework('2'),
        cxHomework('3'),
      ];

  Future<ChaoxingHarness> openHiddenPage(WidgetTester tester,
      {bool deadSecond = false, String? rawMeta}) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks(), seed: <String, Object>{
      ChaoxingPrefs.kHiddenKey: <String>['c1|1', 'c1|2'],
      ChaoxingPrefs.kHiddenMetaKey:
          rawMeta ?? ChaoxingHiddenEntry.encode(entries(deadSecond: deadSecond)),
    });
    await h.pump(tester, width: 411);
    await h.tapIo(tester, h.key(ChaoxingKeys.account));
    await h.tapIo(tester, h.key(ChaoxingKeys.menuHidden));
    return h;
  }

  testWidgets('两行都在，课程名 / 标题 / 截止行都渲染出来', (WidgetTester tester) async {
    final ChaoxingHarness h = await openHiddenPage(tester);

    expect(find.text('隐藏列表'), findsOneWidget);
    expect(find.text('2 项'), findsOneWidget);
    expect(h.key(ChaoxingKeys.hiddenRow('c1|1')), findsOneWidget);
    expect(h.key(ChaoxingKeys.hiddenRow('c1|2')), findsOneWidget);
    expect(find.text('课程甲'), findsOneWidget);
    expect(find.text('第一次作业'), findsOneWidget);
    expect(find.textContaining('截止（剩'), findsOneWidget);
  });

  testWidgets('点某行「恢复」→ 该行消失，回面板后卡片重新出现',
      (WidgetTester tester) async {
    final ChaoxingHarness h = await openHiddenPage(tester);
    expect(h.cardOf(cxHomework('1')), findsNothing); // 面板里被挡住

    await h.tapIo(tester, h.key(ChaoxingKeys.hiddenRestore('c1|1')));

    expect(h.key(ChaoxingKeys.hiddenRow('c1|1')), findsNothing);
    expect(h.model.settings.hidden, isNot(contains('c1|1')));
    expect(h.prefs.getString(ChaoxingPrefs.kHiddenMetaKey),
        isNot(contains('c1|1')));

    await h.tapIo(tester, find.byType(BackButton));
    expect(h.cardOf(cxHomework('1')), findsOneWidget);
  });

  testWidgets('dead 项显示「已失效」并出现「清理已失效」，点它 → 行与 prefs 都没了',
      (WidgetTester tester) async {
    final ChaoxingHarness h = await openHiddenPage(tester, deadSecond: true);

    expect(find.text('已失效'), findsOneWidget);
    expect(h.key(ChaoxingKeys.hiddenPurgeDead), findsOneWidget);
    expect(find.widgetWithText(TextButton, '移除'), findsOneWidget);

    await h.tapIo(tester, h.key(ChaoxingKeys.hiddenPurgeDead));

    expect(h.key(ChaoxingKeys.hiddenRow('c1|2')), findsNothing);
    expect(h.prefs.getString(ChaoxingPrefs.kHiddenMetaKey),
        isNot(contains('c1|2')));
    expect(h.model.settings.hidden, isNot(contains('c1|2')));
  });

  testWidgets('没有 dead 项时不出现「清理已失效」', (WidgetTester tester) async {
    final ChaoxingHarness h = await openHiddenPage(tester);
    expect(h.key(ChaoxingKeys.hiddenPurgeDead), findsNothing);
  });

  testWidgets('元数据是坏 JSON → 显示空态而不是崩', (WidgetTester tester) async {
    await openHiddenPage(tester, rawMeta: '{不是合法 JSON');

    expect(tester.takeException(), isNull);
    expect(find.text('没有隐藏的待办'), findsOneWidget);
    expect(find.text('1 项'), findsNothing);
  });

  testWidgets('全部恢复先问「恢复 N 项？」，确认后才清空',
      (WidgetTester tester) async {
    final ChaoxingHarness h = await openHiddenPage(tester);

    await h.tapIo(tester, h.key(ChaoxingKeys.hiddenRestoreAll));
    expect(find.text('恢复 2 项？'), findsOneWidget);
    await h.tapIo(tester, find.widgetWithText(TextButton, '取消'));
    expect(h.model.settings.hidden.length, 2);

    await h.tapIo(tester, h.key(ChaoxingKeys.hiddenRestoreAll));
    await h.tapIo(tester, find.widgetWithText(FilledButton, '恢复'));
    expect(h.model.settings.hidden, isEmpty);
    expect(h.model.hiddenEntries, isEmpty);
  });

  test('刷新后不再出现的隐藏项被标 dead（不自动删），仍存在的跟着更新截止', () async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(seed: seed());
    // 隐藏集里两条都在，但这次刷新只回了一条，且它的截止时间改了。
    final ChaoxingTask updated = cxHomework('1',
        dueAt: kCxNow.add(const Duration(days: 3)));
    h.client.tasks = <ChaoxingTask>[updated];
    await h.model.refresh();

    final ChaoxingHiddenEntry first = h.model.hiddenEntries
        .firstWhere((ChaoxingHiddenEntry e) => e.key == 'c1|1');
    final ChaoxingHiddenEntry second = h.model.hiddenEntries
        .firstWhere((ChaoxingHiddenEntry e) => e.key == 'c1|2');
    expect(first.dueMs, updated.dueAt!.millisecondsSinceEpoch);
    expect(first.dead, isFalse);
    expect(second.dead, isTrue);
    // dead 不删：留给用户在隐藏列表里自己决定。
    expect(h.model.settings.hidden, contains('c1|2'));
  });
}
