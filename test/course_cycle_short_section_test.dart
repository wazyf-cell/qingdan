// 短节次作息下的循环角标几何（细化 §2.4，2026-10-19 评审第 1 条）。
//
// 块高公式是 `0.9 × 分钟数 − 2`（`section_layout.dart` 的 kMinutesToDp 与
// kBlockInsetDp）：45 分钟一节 = 38.5dp，43 分钟起才真的容得下 36dp 的标称热区，
// 40 分钟一节只有 34dp。而「每节时长」是自由输入（`timetable_generate_form.dart`
// 的 `_intOf(_lesson, 45)`；`time_table.dart` 的 `validateTimeDetails` 只查
// `end > start`），30 / 20 分钟一节的作息**能落库** → 热区与 20dp 圆底都会溢出块。
// 窄屏与宽屏各 pump 一遍（S4b 的教训）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'course_cycle_harness.dart';
import 'dao_test_helper.dart';

void main() {
  ensureSqfliteFfi();

  late CycleEnv env;
  setUp(() async => env = await CycleEnv.open());
  tearDown(() async => env.close());

  /// 30 分钟一节、零课间：块高 25dp，比 36dp 热区矮 11dp。
  /// 第一节放一门独课，第二节挤两门（带角标）——两块之间只差 2dp 内缩，
  /// 漏出去的热区正好盖在上一块的下半部分上。
  Future<(Course above, Course shown)> shortSectionPair(CycleHarness h) async {
    await h.seed(sectionMinutes: 30, gapMinutes: 0);
    final Course above =
        await h.add(name: '甲课', start: 1, end: 1, location: 'A101');
    final Course shown =
        await h.add(name: 'B课', start: 2, end: 2, location: 'B202');
    await h.add(name: 'C课', start: 2, end: 2);
    return (above, shown);
  }

  for (final double width in <double>[411, 1280]) {
    testWidgets('短节次：热区钳到块高、圆底不被裁，越界处归上一块（$width dp）',
        (tester) async {
      final CycleHarness h = CycleHarness(tester, env);
      final (Course above, Course shown) = await shortSectionPair(h);
      await h.pumpGrid(width: width);

      final Rect block = tester.getRect(blockOf(shown.id));
      final Rect hit = tester.getRect(cycleHitArea());
      final Rect circle = tester.getRect(cycleCircle());
      expect(block.height, closeTo(25.0, 0.5), reason: '0.9×30 − 2 = 25dp');
      expect(hit.height, lessThanOrEqualTo(block.height + 0.5),
          reason: '标称 36dp 的热区必须钳进块高：块外那截既画不出来（外层 ClipRect '
              '把绘制剪掉）也点不到（隔壁块吃掉点击），留着就是骗人的热区');
      expect(hit.top, greaterThanOrEqualTo(block.top - 0.5),
          reason: '热区上沿不得越过块的上沿');
      expect(circle.top, greaterThanOrEqualTo(block.top - 0.5),
          reason: '圆底整颗在块内，不会被裁剪掉一截');
      expect(circle.height, lessThanOrEqualTo(AppDimens.courseCycleBadge + 0.5));

      // 上一块下沿往里 4dp：没钳位时这一点落在漏出的热区里（块外 11dp）。
      final Rect aboveRect = tester.getRect(blockOf(above.id));
      await tester.tapAt(Offset(aboveRect.right - 4, aboveRect.bottom - 4));
      await tester.pumpAndSettle();
      expect(find.textContaining('地点：A101'), findsOneWidget,
          reason: '这一下属于上一块的块本体，该开它的详情');
      expect(blockOf(shown.id), findsOneWidget,
          reason: '下面的组不该被这一下切成第二条');
    });
  }
}
