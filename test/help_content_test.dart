import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/settings/help_section.dart';
import 'package:qingdan/theme/app_theme.dart';

/// 使用说明页（M6-C6）。
///
/// 这里测的不只是「有没有渲染」，而是**每一节的文案都对着代码核实过**：
/// 断言的都是实现里真存在的说法（刷新只有两处、应用密码、长按校准、30 分钟兜底、
/// 免打扰顺延、已排提醒仍会响……）。最后一条测试是**反编造闸**：一旦有人把没做的
/// 功能写进来（后台自动刷新、点卡片跳超星、中英切换、检查更新），那几条就红。
void main() {
  Future<void> pumpHelp(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      // 必须走 AppTheme：AppColors.of 读的是它装的主题扩展，裸 MaterialApp 会炸。
      theme: AppTheme.light(),
      home: const HelpPage(),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '${width}dp 渲染有异常');
  }

  const List<String> chapterTitles = <String>[
    '四个页签',
    '清单',
    '学习通',
    '课表',
    '同步',
    '提醒',
  ];

  testWidgets('411dp：六节标题齐全且不溢出', (WidgetTester tester) async {
    await pumpHelp(tester, width: 411);
    expect(find.byKey(const ValueKey<String>('help-page')), findsOneWidget);
    for (final String title in chapterTitles) {
      expect(find.text(title), findsOneWidget, reason: '缺节「$title」');
    }
  });

  testWidgets('1280dp：同样六节（双端各 pump 一次）',
      (WidgetTester tester) async {
    await pumpHelp(tester, width: 1280);
    for (final String title in chapterTitles) {
      expect(find.text(title), findsOneWidget, reason: '缺节「$title」');
    }
  });

  testWidgets('文案与实现一致（逐条核实过的说法）',
      (WidgetTester tester) async {
    await pumpHelp(tester, width: 411);
    const List<String> verified = <String>[
      // 清单：自然语言日期（`due_date_parser.dart` 的短语集与默认时刻）
      '明天下午3点 交周报',
      '默认 09:00',
      '回收站：删除先进这里',
      '7 / 30 / 90 天或永不，默认 30 天',
      '应用启动时 + 应用活着期间每 30 分钟',
      // 学习通（`chaoxing_model.dart` / `chaoxing_pane.dart`）
      '刷新只有两处',
      '距上次拉取不到 15 分钟',
      '没有后台定时刷新，也没有下拉刷新',
      '把卡片往左拖（从右往左滑）',
      '不写进应用数据库、不参与设备间同步',
      '点卡片不会跳转超星',
      // 课表（`course_setup.dart` / `week_picker_sheet.dart` / `schedule_file.dart`）
      '长按那一周 = 把它设为本周',
      '课程没有回收站',
      '.wakeup_schedule',
      '抓当前页',
      '逐行校正 → 确认导入',
      '文件 / 映射 / 学期作息 / 校正 / 导入',
      '合并 / 覆盖 / 仅新增',
      // 同步（`sync_section.dart` / `sync_coordinator.dart` / `sync_slot.dart`）
      '填的是「应用密码」，不是网站登录密码',
      '每 30 分钟兜底轮询',
      '1 → 2 → 4 → 8 → 15 分钟退避',
      '600 请求 / 30 分钟',
      '同步未配置',
      '需要重新配置',
      '限流 · HH:mm 恢复',
      // 提醒（按 `待执行-M6C-设置与通知.md` §C2 定案）
      '没设到期时间的任务不会提醒',
      '默认 23:00–07:00',
      '顺延到区间结束那一刻',
      '已排入的提醒仍会响',
      '新增或改动的待办要等应用下次打开才会重新排程',
      'Windows 端没有系统通知',
    ];
    for (final String phrase in verified) {
      expect(find.textContaining(phrase), findsWidgets,
          reason: '说明里没有这句：$phrase');
    }
  });

  testWidgets('反编造闸：没实现的功能一句都不许出现',
      (WidgetTester tester) async {
    await pumpHelp(tester, width: 411);
    const List<String> notImplemented = <String>[
      '后台自动刷新', // 学习通刻意不后台刷（总纲 §四.4）
      '定时自动拉取学习通', // 刷新只有两处
      '点击卡片可跳转超星', // 用户 2026-10-17 明确不要
      '中英双语切换', // 总纲 §四.1 不做
      // 「检查更新」这一条在 v1.0.2 起从本清单删掉了：它已经从占位变成真控件
      // （设置 → 通用 → 检测更新 / GitHub 仓库），再钉在这里就是禁止说明书写一件
      // 已经存在的能力。它现在受另一条测试管：test/settings_update_rows_test.dart。
      '自建服务器', // 需求定死的约束
    ];
    for (final String phrase in notImplemented) {
      expect(find.textContaining(phrase), findsNothing,
          reason: '说明里写了不存在的能力：$phrase');
    }
  });

  testWidgets('正文里不许漏 markdown 星号（Flutter 不渲染，用户会看见字面 **）',
      (WidgetTester tester) async {
    await pumpHelp(tester, width: 411);
    final Iterable<String> rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data ?? '');
    expect(rendered.where((String s) => s.contains('**')), isEmpty,
        reason: '说明正文用的是普通 Text，** 只会以星号原样出现在屏幕上');
  });

  testWidgets('内容能滚动看完（最后一句在滚动后进入视口）',
      (WidgetTester tester) async {
    await pumpHelp(tester, width: 411);
    final String last = '以上就是当前真实有的功能。界面以后有改动，这一页会跟着改文案。';
    final double before = tester.getTopLeft(find.text(last)).dy;
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text(last)).dy, lessThan(before),
        reason: '正文不可滚动：手机上看不完');
  });
}
