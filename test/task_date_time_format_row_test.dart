// 任务日期/时刻：纯函数 + 日期行组件（M6-A §A3；自 `task_date_time_test.dart`
// 按被测对象拆出，断言一条未改）。
//
// 真 `TimePickerDialog`（表盘要拖、文本模式又看 locale 的 12/24 小时制）在
// FakeAsync 里驱动只会得到一条不稳的端到端，所以选择器用行组件的接缝注入假结果，
// **写路径与库都是真的**（`QuickComposeSheet` → `TaskPaneModel.createQuickAdd` →
// `TaskUseCase.create` → `TaskDao.insert`），时分合成规则由 `applyTime` 单测钉住。
// 双端各 pump 一次（411 移动 / 1280 桌面）。
//
// 抽屉那两条在 `task_date_time_compose_test.dart`，详情面板三条在
// `task_date_time_detail_test.dart`；共用夹具在 `task_date_time_harness.dart`。
// `_RowHost` 只有本文件的「日期行」用例用，就留在这里保持私有原名。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/tasks/compose_date_time_row.dart';
import 'package:qingdan/features/tasks/date_time_pick.dart';
import 'package:qingdan/features/tasks/due_format.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'task_date_time_harness.dart';
import 'tasks_harness.dart';

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
}
