import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/compose_date_time_row.dart';
import 'package:qingdan/features/tasks/date_time_pick.dart';
import 'package:qingdan/features/tasks/detail_attributes.dart';
import 'package:qingdan/features/tasks/due_format.dart';
import 'package:qingdan/features/tasks/quick_compose_sheet.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'tasks_harness.dart';

// M6-A §A3：`startDate` / `endDate` / `dueDate` 三个字段支持**可选**的时分。
//
// 真 `TimePickerDialog`（表盘要拖、文本模式又看 locale 的 12/24 小时制）在
// FakeAsync 里驱动只会得到一条不稳的端到端，所以选择器用行组件的接缝注入假结果，
// **写路径与库都是真的**（`QuickComposeSheet` → `TaskPaneModel.createQuickAdd` →
// `TaskUseCase.create` → `TaskDao.insert`），时分合成规则由 `applyTime` 单测钉住。
// 双端各 pump 一次（411 移动 / 1280 桌面）。

/// 注入：点日期行直接得到 [d]。
DateFieldPicker pickDateTo(DateTime d) =>
    (_, _) async => d;

/// 注入：点时刻钮就按生产同款纯函数 [applyTime] 把 [t] 合到当前值上。
DateFieldPicker pickTimeTo(TimeOfDay t) =>
    (BuildContext _, DateTime? current) async {
      final DateTime? v = current;
      return v == null ? null : applyTime(v, t);
    };

/// 把待测界面**推进导航栈**，而不是当根路由：抽屉点「添加」最后会 `Navigator.pop()`，
/// 根路由被 pop 会让 Navigator 变空，之后的断言就没了落点。
Future<void> pumpHost(
    WidgetTester tester, TasksHarness h, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SidebarModel>.value(value: h.sidebar),
        ChangeNotifierProvider<TaskPaneModel>.value(value: h.paneModel),
      ],
      // 裸 MaterialApp 会让 AppColors.of(context) 抛（主题扩展只由 AppTheme 装）。
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => TextButton(
              key: const ValueKey<String>('host-push'),
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                  // 必须给一个 Material 祖先：行组件用的是 InkWell，裸路由会让它
                  // 直接断言失败（生产里抽屉/弹层都自带 Material，所以只有测试会踩）。
                  builder: (_) => Material(child: child))),
              child: const Text('进入被测界面'),
            ),
          ),
        ),
      ),
    ),
  );
  await h.tapIo(tester, find.byKey(const ValueKey<String>('host-push')));
}

/// 取某一行当前显示的值文案。
String rowValueText(WidgetTester tester, String rowKey) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(ValueKey<String>(rowKey)), matching: find.byType(Text)))
    .data ??
    '';

/// 读库里那条标题对应的任务。
Future<Task> taskInDb(WidgetTester tester, TasksHarness h, String title) async {
  final List<Task>? all =
      await h.io(tester, () => h.taskUseCase.findAllActive());
  return all!.firstWhere((Task t) => t.title == title);
}

/// 自带 state 的行宿主。
///
/// 为什么不用 `pumpHost`：`ComposeDateTimeRow` 是**受控**组件（`value` 由外部传），
/// 而 `pumpHost` 每次 `pumpWidget` 都会新推一条路由，第一条路由的 builder 已经把
/// 老的 `row(null)` 捕获住了——第二次推 `row(新值)` 时断言读到的还是老路由的值，
/// 于是「点了日期，文案该变」这条永远看不到变化（实测报 `'未设置'`）。
/// 自己持有 `_v` 并在 `onChanged` 里 `setState`，才是真实交互的形状。
class _RowHost extends StatefulWidget {
  const _RowHost({required this.emitted});

  final List<DateTime?> emitted;

  @override
  State<_RowHost> createState() => _RowHostState();
}

class _RowHostState extends State<_RowHost> {
  DateTime? _v;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: ComposeDateTimeRow(
        rowKey: 'row-x',
        label: '到期',
        value: _v,
        pickDate: pickDateTo(DateTime(2026, 10, 18)),
        pickTime: pickTimeTo(const TimeOfDay(hour: 14, minute: 30)),
        onChanged: (DateTime? v) {
          widget.emitted.add(v);
          setState(() => _v = v);
        },
      ),
    );
  }
}

void main() {
  TasksHarness.boot();

  late TasksHarness h;
  setUp(() async {
    h = TasksHarness();
    await h.start();
  });
  tearDown(() => h.stop());

  group('纯函数', () {
    test('formatTaskDate：00:00 视为没填时间', () {
      expect(formatTaskDate(null), '未设置');
      expect(formatTaskDate(DateTime(2026, 10, 18)), '10-18',
          reason: '只选日期 → 不显示时间');
      expect(formatTaskDate(DateTime(2026, 10, 18, 14, 30)), '10-18 14:30');
      expect(formatTaskDate(DateTime(2026, 1, 5, 9)), '01-05 09:00',
          reason: '月/日/时/分都补零');
      expect(formatTaskDate(DateTime(2026, 10, 18, 0, 30)), '10-18 00:30',
          reason: '00:30 是填了时间（只有 00:00 算没填）');
    });

    test('applyTime 与 preserveTime：改日期不该抹掉已填的时刻', () {
      expect(applyTime(DateTime(2026, 10, 18), const TimeOfDay(hour: 14, minute: 30)),
          DateTime(2026, 10, 18, 14, 30));
      expect(preserveTime(DateTime(2026, 10, 18, 14, 30), DateTime(2026, 11, 2)),
          DateTime(2026, 11, 2, 14, 30));
      expect(preserveTime(DateTime(2026, 10, 18), DateTime(2026, 11, 2)),
          DateTime(2026, 11, 2));
      expect(preserveTime(null, DateTime(2026, 11, 2)), DateTime(2026, 11, 2));
    });
  });

  testWidgets('日期行：三态文案 + 时刻钮与 ✕ 的 key/行为', (tester) async {
    final List<DateTime?> emitted = <DateTime?>[];
    tester.view.physicalSize = const Size(411, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: _RowHost(emitted: emitted)),
    );

    expect(rowValueText(tester, 'row-x'), '未设置');
    expect(find.byKey(const ValueKey<String>('row-x-time')), findsNothing,
        reason: '没有日期时不出现时刻钮');
    expect(find.byKey(const ValueKey<String>('row-x-clear')), findsNothing);

    // 点日期 → 注入的选择器给 10-18 → 宿主重绘，文案当场就该变（不用重新推路由）。
    await h.tapIo(tester, h.key('row-x'));
    expect(emitted.last, DateTime(2026, 10, 18));
    expect(rowValueText(tester, 'row-x'), '10-18',
        reason: '只填日期不填时刻 → 不带时间');
    expect(find.text('无时间'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('row-x-time')), findsOneWidget);

    await h.tapIo(tester, h.key('row-x-time'));
    expect(emitted.last, DateTime(2026, 10, 18, 14, 30));
    expect(rowValueText(tester, 'row-x'), '10-18 14:30');

    await h.tapIo(tester, h.key('row-x-clear'));
    expect(emitted.last, isNull, reason: '✕ 清空整个字段（日期 + 时刻一起）');
    expect(rowValueText(tester, 'row-x'), '未设置',
        reason: '清空后回到未填态，时刻钮与 ✕ 一起消失');
    expect(find.byKey(const ValueKey<String>('row-x-time')), findsNothing);
    expect(find.byKey(const ValueKey<String>('row-x-clear')), findsNothing);
  });

  testWidgets('抽屉「到期」：日期 + 14:30 真的落库（411 移动壳）',
      (tester) async {
    await pumpHost(
      tester,
      h,
      411,
      QuickComposeSheet(
        pickDate: pickDateTo(DateTime(2026, 10, 18)),
        pickTime: pickTimeTo(const TimeOfDay(hour: 14, minute: 30)),
      ),
    );
    await tester.enterText(h.key('compose-title'), '交实验报告');
    await tester.pump();

    await h.tapIo(tester, h.key('compose-due'));
    expect(rowValueText(tester, 'compose-due'), '10-18');
    await h.tapIo(tester, h.key('compose-due-time'));
    expect(rowValueText(tester, 'compose-due'), '10-18 14:30');

    await h.tapIo(tester, h.key('compose-save'));

    final Task made = await taskInDb(tester, h, '交实验报告');
    // 库里存 UTC 毫秒，读回来是 UTC → 断言走 toLocal()。
    // 直接看 `made.dueDate!.hour` 在本机（UTC+8）会得到 6，那是时区不是精度丢失。
    expect(made.dueDate, isNotNull);
    expect(made.dueDate!.toLocal().hour, 14);
    expect(made.dueDate!.toLocal().minute, 30);
    expect(made.dueDate!.toLocal(), DateTime(2026, 10, 18, 14, 30));
  });

  testWidgets('抽屉「开始」带时刻并支持清除（1280 桌面壳）', (tester) async {
    await pumpHost(
      tester,
      h,
      1280,
      QuickComposeSheet(
        pickDate: pickDateTo(DateTime(2026, 11, 2)),
        pickTime: pickTimeTo(const TimeOfDay(hour: 8, minute: 5)),
      ),
    );
    await tester.enterText(h.key('compose-title'), '桌面用例');
    await tester.pump();

    await h.tapIo(tester, h.key('compose-start'));
    expect(rowValueText(tester, 'compose-start'), '11-02');
    await h.tapIo(tester, h.key('compose-start-time'));
    expect(rowValueText(tester, 'compose-start'), '11-02 08:05');
    await h.tapIo(tester, h.key('compose-start-clear'));
    expect(rowValueText(tester, 'compose-start'), '未设置');

    await h.tapIo(tester, h.key('compose-save'));
    final Task made = await taskInDb(tester, h, '桌面用例');
    expect(made.startDate, isNull, reason: '✕ 清掉后不该把日期又写回去');
    expect(made.dueDate, isNull);
  });

  testWidgets('详情「到期」行：没有外部回调也经既有用例路径落库', (tester) async {
    final List<Task>? all =
        await h.io(tester, () => h.taskUseCase.findAllActive());
    final Task target =
        all!.firstWhere((Task t) => t.title == '交开题'); // 这条没有到期日
    expect(target.dueDate, isNull);

    await pumpHost(
      tester,
      h,
      411,
      DetailAttributes(
        task: target,
        lists: h.paneModel.lists,
        onPickList: (_) {},
        onPickPriority: (_) {},
        onPickStartDate: (_) {},
        onPickEndDate: (_) {},
        // 不传 onPickDueDate：走 detail_attributes 内部那条兜底写路径。
        pickDate: pickDateTo(DateTime(2026, 10, 18, 14, 30)),
      ),
    );
    expect(rowValueText(tester, 'detail-due'), '未设置');
    expect(find.byKey(const ValueKey<String>('detail-due-clear')), findsNothing,
        reason: '详情面板写不回 null，所以不给假能点的 ✕');

    await h.tapIo(tester, h.key('detail-due'));
    final Task saved = await taskInDb(tester, h, '交开题');
    expect(saved.dueDate!.toLocal().hour, 14);
    expect(saved.dueDate!.toLocal().minute, 30);
  });

  testWidgets('窄屏全屏详情页：开始 / 结束 / 到期三行齐全（411）',
      (tester) async {
    await h.pumpAtWidth(tester, 411);
    await h.tapIo(tester, find.text('买牛奶'));
    for (final String key in <String>[
      'detail-start',
      'detail-end',
      'detail-due',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: '缺 $key');
    }
    // 买牛奶的到期日是 `DateTime.now()` 建的（带时刻），这一行必须把时分显示出来。
    final Task milk = await taskInDb(tester, h, '买牛奶');
    final DateTime local = milk.dueDate!.toLocal();
    expect(
        rowValueText(tester, 'detail-due'),
        '${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}',
        reason: '详情「到期」行要把已存的时分显示出来');
  });

  testWidgets('桌面详情面板：三行齐全且不溢出（1280）', (tester) async {
    await h.pumpAtWidth(tester, 1280);
    await h.tapIo(tester, find.text('买牛奶'));
    for (final String key in <String>[
      'detail-start',
      'detail-end',
      'detail-due',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: '缺 $key');
    }
  });
}
