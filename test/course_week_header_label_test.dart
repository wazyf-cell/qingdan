import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/course/course_week_header.dart';
import 'package:qingdan/features/course/semester_switcher.dart';
import 'package:qingdan/theme/app_theme.dart';

/// 周次标签在 411dp 窄屏被省略号截断（真机截图 2026-10-19：「第 10 周 / 共 16 …」）。
///
/// 判据用渲染层的硬事实，不用「找到了 widget」这种弱断言：
/// * `RenderParagraph.didExceedMaxLines` —— 文本真的处于 ellipsized 状态时为 true；
/// * `size.width >= getMaxIntrinsicWidth(...)` —— 布局宽度装得下整行文案；
/// * `Text.data` 本身完整（钉住「共 M 周」没被谁悄悄删掉）。
///
/// 头部单独 pump（不接 CoursePane / 数据库）：这一行的宽度预算只取决于
/// `CourseWeekHeader` 自己的 children，学期名按钮按真实用法塞进来即可复现挤压。
void main() {
  Future<void> pumpHeader(
    WidgetTester tester, {
    required double width,
    required bool isMobile,
    required int week,
    required int totalWeeks,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CourseWeekHeader(
            week: week,
            totalWeeks: totalWeeks,
            canPrev: true,
            canNext: true,
            isMobile: isMobile,
            onPrev: () {},
            onNext: () {},
            onToday: () {},
            onToggleWeekend: () {},
            onAddCourse: () {},
            onOpenSetup: () {},
            // 桌面才有导入按钮（既有定案），移动端不给——复现真机同一排布。
            onImport: isMobile ? null : () {},
            onPickWeek: () {},
            // 学期名取到能撑满 120dp 上限的长度 = 最坏挤压场景。
            semesterSwitcher: SemesterSwitcher(
                name: '2025-2026-1 秋季学期', isMobile: isMobile),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 断言 `week-label` 这坨文字**没有被截断**：三判据全上，任何一条退化都能抓到。
  void expectLabelComplete(WidgetTester tester) {
    final Finder finder =
        find.byKey(const ValueKey<String>('week-label'));
    final Text text = tester.widget<Text>(finder);
    expect(text.data, isNotNull);
    final RenderParagraph rp = tester.renderObject<RenderParagraph>(finder);
    // 整行文案在原字号下需要的宽度。
    final double need = rp.getMaxIntrinsicWidth(rp.size.height);
    expect(rp.didExceedMaxLines, isFalse,
        reason: '「${text.data}」正被省略号截断（布局宽 ${rp.size.width} < 需要 $need）');
    expect(rp.size.width, greaterThanOrEqualTo(need - 0.5),
        reason: '标签的布局宽度装不下整行文案：${rp.size.width} < $need');
    expect(tester.takeException(), isNull, reason: '头部一行不得出现 RenderFlex 溢出');
  }

  testWidgets('手机 411dp：两位数周「第 10 周 / 共 16 周」不被截断', (tester) async {
    await pumpHeader(tester, width: 411, isMobile: true, week: 10, totalWeeks: 16);
    expectLabelComplete(tester);
    expect(find.text('第 10 周 / 共 16 周'), findsOneWidget,
        reason: '「共 M 周」不许为了塞下而删掉（用户靠它判断学期长度）');
  });

  testWidgets('手机 411dp：三位数周「第 30 周 / 共 30 周」（总周数上限 30）也完整',
      (tester) async {
    await pumpHeader(tester, width: 411, isMobile: true, week: 30, totalWeeks: 30);
    expectLabelComplete(tester);
  });

  testWidgets('桌面 1280dp 对照：标签完整且字号未被缩放', (tester) async {
    await pumpHeader(
        tester, width: 1280, isMobile: false, week: 10, totalWeeks: 16);
    expectLabelComplete(tester);
    // 宽屏余量充足，FittedBox 的 scaleDown 不该产生任何缩放（16sp 定案不破）：
    // 视觉矩形（含祖先变换）的宽必须等于原字号下需要的宽。
    final double need = tester
        .renderObject<RenderParagraph>(
            find.byKey(const ValueKey<String>('week-label')))
        .size
        .width;
    expect(tester.getRect(find.byKey(const ValueKey<String>('week-label'))).width,
        closeTo(need, 0.5),
        reason: '桌面端周次标签被缩字号了——这是窄屏让步策略，不该泄漏到宽屏');
  });
}
