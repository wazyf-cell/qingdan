import 'package:flutter/material.dart';

import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_palette.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 课程配色选择器（M6-D §十）：8 个色点 + 一个「自动」。
///
/// 为什么必须有「自动」这一档：`color_index` 是可空列，空 = 沿用按课名派生的
/// 配色（跨设备稳定）。用户选过颜色又改回去，必须能把列清成 null，
/// 而不是留着一个和课名一样的值——那样以后改名就不会再跟着变了。
///
/// 色值本身由 `test/palette_contrast_test.dart` 钉住（S5-0 那 11 条对比度断言），
/// 这里只画，不改。
class CourseColorPicker extends StatelessWidget {
  const CourseColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.courseName = '',
  });

  /// null = 自动配色（跟随课名）。
  final int? value;
  final ValueChanged<int?> onChanged;

  /// 「自动」那一档旁边显示它当前会落到哪一色，用户才知道这一档不是「没颜色」。
  final String courseName;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    final int autoIndex =
        courseName.isEmpty ? 0 : courseColorIndex(courseName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('颜色',
            style: AppTypography.meta.copyWith(color: colors.textSecondary)),
        const SizedBox(height: AppDimens.s4),
        Wrap(
          spacing: AppDimens.s8,
          runSpacing: AppDimens.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (int i = 0; i < kCoursePaletteSize; i++)
              _Swatch(
                keyName: 'field-color-$i',
                color: CoursePalette.of(brightness, i),
                selected: value == i,
                onTap: () => onChanged(i),
              ),
            TextButton.icon(
              key: const ValueKey<String>('field-color-auto'),
              onPressed: () => onChanged(null),
              icon: Icon(Icons.autorenew,
                  size: 16,
                  color: value == null ? colors.accent : colors.textFaint),
              label: Text(
                value == null ? '自动（当前第 ${autoIndex + 1} 号）' : '自动',
                style: AppTypography.meta.copyWith(
                    color: value == null ? colors.accent : colors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 一个色点：选中态是白对勾 + 外圈描边（不靠「变大」表达选中，窄屏点距只有 8dp）。
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.keyName,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String keyName;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      key: ValueKey<String>(keyName),
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        margin: EdgeInsets.all(selected ? 1 : 3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? colors.textPrimary : colors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}
