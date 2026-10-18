import 'package:flutter/material.dart';

/// 课表 8 色调色板（细化 §0:19「调色板色 ×8（索引 0-7）」）。
///
/// 设计稿故意只给语义名不给色值，这 8 组是 2026-10-10 按 M1 §1.2 的低饱和体系
/// 补定的（用户授权），并已作为勘误写回细化 §0。取色原则：**不与语义色撞义**——
/// 避开 overdue 红 `#D93025`、success 绿 `#30A46C`、accent 蓝 `#4263EB` 与三档
/// 优先级色，免得课块底色被读成「这门课有问题」。
///
/// 三处用法（细化 §2.3:86-90）：块底 = 色板色 16% 透明、左条 = 实色 3dp、
/// 课名 = 同色的**前景变体**（浅色主题加深、深色主题提亮，见 [foreground])。
abstract final class CoursePalette {
  /// 块底透明度（细化 §2.3:86）。
  static const double blockBackgroundOpacity = 0.16;

  /// 浅色主题 8 色。
  static const List<Color> light = <Color>[
    Color(0xFF0E7C86), // 0 松石
    Color(0xFF6741D8), // 1 靛紫
    Color(0xFFA61E7E), // 2 洋红
    Color(0xFF8A6D1F), // 3 古铜
    Color(0xFF4A5568), // 4 石墨
    Color(0xFF2F6B4F), // 5 森绿
    Color(0xFF9A5B24), // 6 赭石
    Color(0xFF1C6E9B), // 7 海蓝
  ];

  /// 深色主题 8 色（按 M1 §1.2:19 的「提亮 20%、降饱和 8%」同族规则推导）。
  static const List<Color> dark = <Color>[
    Color(0xFF3FA9B5),
    Color(0xFFA08AE0),
    Color(0xFFD958A8),
    Color(0xFFD2A54A),
    Color(0xFF8B95A5),
    Color(0xFF6FB894),
    Color(0xFFC98A4B),
    Color(0xFF58A9D6),
  ];

  /// 索引取色（索引由 `courseColorIndex` 按课名派生，恒 0..7）。
  static Color of(Brightness brightness, int index) =>
      (brightness == Brightness.dark ? dark : light)[index % 8];

  /// 课程块底色：色板色 16% 叠在 surface 上。
  static Color blockBackground(Brightness brightness, int index) =>
      of(brightness, index).withValues(alpha: blockBackgroundOpacity);

  /// 课名前景色变体：浅色主题加深（L −25%、S +10%），深色主题提亮（L +20%、
  /// S −8%，与 M1 §1.2:19 的深色语义色规则一致）。
  ///
  /// 公式在此定案（设计稿只写「加深变体」未给公式）。
  static Color foreground(Brightness brightness, int index) {
    final HSLColor hsl = HSLColor.fromColor(of(brightness, index));
    if (brightness == Brightness.dark) {
      return hsl
          .withLightness((hsl.lightness + 0.20).clamp(0.0, 1.0))
          .withSaturation((hsl.saturation - 0.08).clamp(0.0, 1.0))
          .toColor();
    }
    return hsl
        .withLightness((hsl.lightness - 0.25).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }
}
