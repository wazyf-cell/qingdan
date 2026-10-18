// 同槽循环角标与组内计数（细化 §2.4，2026-10-19 改版）。
//
// 一个组里当前周确实有 ≥2 门课时：块右下角挂 [CourseCycleBadge]（点它切到组内
// 下一条），总数 > 2 时再在块内右上角挂 [CourseCycleCounter]（「2/3」小字）。
// 取代旧形态：均分堆叠 + 挤不下时整组压成「首二字 + +N」降级块（那两个组件与
// `OverlapGroup.badgeCount` 一并删除）。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_palette.dart';

/// 循环角标：视觉 20dp 圆底、点击热区 36dp（**不超过所在课程块的高度**）。
///
/// 圆底取**这门课自身调色板色的加深变体**（[CoursePalette.foreground]，浅色主题
/// 是 L−25%/S+10% 的那一档，深色主题按同族规则是提亮档），图标用 `surface`——
/// 浅色主题下 surface 就是纯白，正是「白色图标」；深色主题下圆底本身是亮色，
/// 再压纯白只剩 1.9:1，所以反色取表面色（`test/palette_contrast_test.dart`
/// 已钉住 foreground vs 块底 ≥4.5:1，这里就是同一对颜色的对调）。
/// **不用红色**：`colors.overdue` 在本调色板里是「逾期/紧急」语义，拿它标
/// 「还有另一门课」会被读成警报（2026-10-19 用户裁决）。
class CourseCycleBadge extends StatelessWidget {
  const CourseCycleBadge({
    super.key,
    required this.colorIndex,
    required this.hiddenCount,
    required this.maxHeight,
    required this.onTap,
  });

  final int colorIndex;

  /// 组内还没在显示的条数（= 总数 − 1），只进文案，不画数字。
  final int hiddenCount;

  /// 所在课程块的高度：热区钳成 `min(36, maxHeight)`。
  ///
  /// **为什么要钳**：块高 = `0.9 × 分钟数 − 2`，一节排到 43 分钟以下就不足 36dp，
  /// 而每节时长是自由输入（30 分钟能落库）。不钳的话热区会往上顶出块外——那一段
  /// 被块的 `ClipRect` 剪掉，实测**点不到**（2026-10-19 探针：命中的是上一块的
  /// 手势层），于是标称 36dp 的热区名存实亡；20dp 圆底也会被剪一截。
  final double maxHeight;
  final VoidCallback onTap;

  /// 文案集中在这一处：Tooltip、Semantics 与无障碍读到的必须是同一句。
  static String labelFor(int hiddenCount) =>
      '该时段还有 $hiddenCount 门课，点击查看下一门';

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    final String label = labelFor(hiddenCount);
    // 热区随块高收缩；圆底与图标再随热区收缩（正常块高下三者分别 = 36 / 20 / 14，
    // 与原设计一致，一个像素都不变）。
    final double target = math.min(AppDimens.courseCycleTouchTarget, maxHeight);
    final double circle = math.min(AppDimens.courseCycleBadge, target);
    final double glyph = math.min(14.0, circle * 0.7);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        // 光有 label + button 只让读屏**读得到**；不给 tap action，TalkBack 双击
        // 上去没有反应，等于这个入口对无障碍用户不存在（2026-10-19 评审第 4 条）。
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // 热区 `target` 方形、圆底 `circle` 居中：Container 给了宽高会把子组件
          // 约束成 20，所以显式 alignment 让图标按自己的尺寸画。
          child: SizedBox(
            width: target,
            height: target,
            child: Center(
              child: Container(
                key: const ValueKey<String>('cycle-badge-circle'),
                width: circle,
                height: circle,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CoursePalette.foreground(brightness, colorIndex),
                ),
                child: Icon(Icons.sync_alt, size: glyph, color: colors.surface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 组内计数小字「2/3」= 当前是第几条 / 共几条。
///
/// 只在总数 > 2 时画（总数 == 2 时 ⇄ 本身已经说明只有一条备选，数字是噪音）。
class CourseCycleCounter extends StatelessWidget {
  const CourseCycleCounter({
    super.key,
    required this.colorIndex,
    required this.index,
    required this.total,
  });

  final int colorIndex;

  /// 0 起的当前索引。
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Text(
      '${index + 1}/$total',
      key: const ValueKey<String>('cycle-counter-text'),
      textDirection: TextDirection.ltr,
      style: TextStyle(
        fontSize: 10,
        height: 12 / 10,
        fontWeight: FontWeight.w600,
        // 与课名同色：test/palette_contrast_test.dart 钉的就是这一对（≥4.5:1）。
        color: CoursePalette.foreground(brightness, colorIndex),
      ),
    );
  }
}
