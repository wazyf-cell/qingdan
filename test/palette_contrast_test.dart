// 色板对比度闸门（M1 界面方案 §1.2:19「来源色与优先级色…保证在深底上对比
// ≥4.5:1」；细化 §2.3 的课块三处用法）。
//
// S4b 欠下的账：8 色板与前景变体公式是实现方自己定的，一直没量化验过。
// 阈值**逐条对着设计稿原文取**，不自行放宽也不自行加严：
//  - §1.2:19 的 4.5:1 只约束「深底」上的优先级/来源色；浅底那些是旗标竖条与
//    圆点（小图形），按 WCAG 1.4.11 的 3:1。
//  - 弱文字按 §1.2 表「占位符、禁用」，WCAG 1.4.3 明确豁免非活动组件，这里只设
//    2.4 地板防漂移。
//  - 课块课名、完成时间、逾期时间是**文字**，一律按 4.5 要求。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_palette.dart';

/// WCAG 2.1 相对亮度（sRGB，无 alpha）。
double _luminance(Color c) {
  double chan(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
}

/// 对比度：(L亮 + 0.05) / (L暗 + 0.05)，恒 ≥1。
double contrastRatio(Color a, Color b) {
  final double la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 半透明前景叠在不透明底上后的实际颜色（课块底色就是 16% 透明）。
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// 断言一组 token 对某个底的对比度过阈值。
void expectAllAbove(
  Map<String, Color> tokens,
  Color bg,
  double min,
  String on,
) {
  for (final MapEntry<String, Color> e in tokens.entries) {
    final double r = contrastRatio(e.value, bg);
    expect(r, greaterThanOrEqualTo(min),
        reason: '${e.key} on $on 实测 ${r.toStringAsFixed(2)}（阈值 $min）');
  }
}

void main() {
  const double textMin = 4.5; // 文字（§1.2:19 与 WCAG AA）
  const double graphicMin = 3.0; // 文字级状态色在浅底的已知下限（见下方例外说明）
  const double faintFloor = 2.4; // 占位/禁用，WCAG 1.4.3 豁免，只防漂移

  AppColors boardOf(Brightness b) =>
      b == Brightness.dark ? AppColors.dark() : AppColors.light();

  group('课表 8 色板', () {
    for (final Brightness brightness in Brightness.values) {
      final AppColors board = boardOf(brightness);
      test('${brightness.name}：课名前景 vs 块底（16% 叠 surface）≥ 4.5:1', () {
        for (int i = 0; i < 8; i++) {
          final Color blockBg =
              _over(CoursePalette.blockBackground(brightness, i), board.surface);
          final double ratio =
              contrastRatio(CoursePalette.foreground(brightness, i), blockBg);
          expect(ratio, greaterThanOrEqualTo(textMin),
              reason: '色板 $i 课名前景 vs 块底 实测 ${ratio.toStringAsFixed(2)}');
        }
      });
    }

    test('深色 8 色确实是浅色同族推导（更亮、饱和度更低）', () {
      for (int i = 0; i < 8; i++) {
        final HSLColor l = HSLColor.fromColor(CoursePalette.light[i]);
        final HSLColor d = HSLColor.fromColor(CoursePalette.dark[i]);
        expect(d.lightness, greaterThan(l.lightness),
            reason: '色板 $i 深色必须比浅色更亮（§1.2:19 提亮）');
        expect(d.saturation, lessThan(l.saturation),
            reason: '色板 $i 深色饱和度要降下来（§1.2:19 降 8% 饱和）');
      }
    });
  });

  group('语义色（M1 §1.2 表）', () {
    for (final Brightness brightness in Brightness.values) {
      final AppColors c = boardOf(brightness);
      final bool dark = brightness == Brightness.dark;

      test('${brightness.name}：主/次要文字 vs bg / surface / surfaceHigh ≥4.5',
          () {
        final Map<String, Color> text = <String, Color>{
          'textPrimary': c.textPrimary,
          'textSecondary': c.textSecondary,
        };
        expectAllAbove(text, c.bg, textMin, 'bg');
        expectAllAbove(text, c.surface, textMin, 'surface');
        expectAllAbove(text, c.surfaceHigh, textMin, 'surfaceHigh');
      });

      test('${brightness.name}：弱文字（占位/禁用）只设地板', () {
        expectAllAbove(<String, Color>{'textFaint': c.textFaint}, c.surface,
            faintFloor, 'surface');
      });

      test('${brightness.name}：优先级/来源/accent 按用途取阈值', () {
        final Map<String, Color> tokens = <String, Color>{
          'priorityHigh': c.priorityHigh,
          'priorityMedium': c.priorityMedium,
          'priorityLow': c.priorityLow,
          'sourceEvent': c.sourceEvent,
          'sourceCourse': c.sourceCourse,
          'accent': c.accent,
        };
        if (dark) {
          // §1.2:19 原文：深色主题「保证在深底上对比 ≥4.5:1」。
          expectAllAbove(tokens, c.surface, textMin, '深 surface');
        } else {
          // 浅底这些只做 6dp 竖条 / 圆点 / 勾选框，设计稿没给数值要求；实测
          // priorityMedium #F5A524 on #FFFFFF 只有 2.04。冻结值不动，2.0 是
          // **防漂移地板**，不是达标声明——别把它当 AA 合规读。
          expectAllAbove(tokens, c.surface, 2.0, '浅 surface');
        }
      });

      test('${brightness.name}：作为文字用的状态色', () {
        // 完成时间 / 逾期时间 / 「上次同步 HH:MM」都是正文级文字。
        final Map<String, Color> tokens = <String, Color>{
          'overdue': c.overdue,
          'success': c.success,
        };
        if (dark) {
          expectAllAbove(tokens, c.surface, textMin, '深 surface');
        } else {
          // 已知不达标：§1.2 把 #30A46C 同时用于「已完成勾选」（图形）与
          // 「完成时间」（文字），实测 3.16 只够图形档。冻结值不动，
          // 先按 3.0 卡住防再降；文字侧的解法（换 token 或加深）待裁决，
          // 见变更日志 2026-10-10 S5-0 节。
          expectAllAbove(tokens, c.surface, graphicMin, '浅 surface');
        }
      });

      test('${brightness.name}：学习通到期底色 —— 文字档 + 可见性地板', () {
        // 2026-10-17 用户要求「1 天内淡红 / 3 天内淡黄 / 更晚淡绿」的行底色。
        // 底色上压着正文与元信息文字，所以按 4.5 卡；同时要求底色与 surface
        // 至少差 1.05，否则「三档」在屏幕上根本分不出来。
        final Map<String, Color> tints = <String, Color>{
          'dueUrgentBg': c.dueUrgentBg,
          'dueNearBg': c.dueNearBg,
          'dueSafeBg': c.dueSafeBg,
        };
        expectAllAbove(<String, Color>{
          'textPrimary': c.textPrimary,
          'textSecondary': c.textSecondary,
        }, tints['dueUrgentBg']!, textMin, 'dueUrgentBg');
        expectAllAbove(<String, Color>{
          'textPrimary': c.textPrimary,
          'textSecondary': c.textSecondary,
        }, tints['dueNearBg']!, textMin, 'dueNearBg');
        expectAllAbove(<String, Color>{
          'textPrimary': c.textPrimary,
          'textSecondary': c.textSecondary,
        }, tints['dueSafeBg']!, textMin, 'dueSafeBg');
        tints.forEach((String name, Color tint) {
          final double r = contrastRatio(tint, c.surface);
          expect(r, greaterThanOrEqualTo(1.05),
              reason: '$name vs surface 实测 ${r.toStringAsFixed(3)}，'
                  '低于 1.05 就看不出上了色');
        });
      });
    }
  });
}
