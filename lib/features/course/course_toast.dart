import 'dart:async';

import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

// 课表页顶部的行内回执（M6-A A5 校准 / A6 删除共用）。
//
// 不用 SnackBar：课表域大量回执发生在模态弹层里，SnackBar 画在弹层路由**下面**，
// 用户完全看不见（2026-10-18 模拟器实测）。既然设置弹层里已经是「贴在内容下方的
// 一行字」（`course_setup.dart` 的 `_Said`），校准与删除也走同一种形状。
const Duration kCourseToastFade = Duration(milliseconds: 250);
const Duration kCourseToastLifetime = Duration(seconds: 3);

/// 回执的持有者：一条消息 + 3 秒后淡出并收起。
class CourseToastController extends ChangeNotifier {
  String? _text;
  bool _opaque = false;
  Timer? _timer;

  String? get text => _text;
  bool get opaque => _opaque;

  void show(String message) {
    _timer?.cancel();
    _text = message;
    _opaque = true;
    notifyListeners();
    // 先淡出（这一行仍占位 250ms），再整条收起，免得布局突然跳一下。
    _timer = Timer(kCourseToastLifetime, () {
      _opaque = false;
      notifyListeners();
      _timer = Timer(kCourseToastFade, clear);
    });
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    if (_text == null) return;
    _text = null;
    _opaque = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// 回执本体。放在周次头部下方**单独一行**，不挤占周次标签的横向空间（S4b 事故）。
class CourseToastLine extends StatelessWidget {
  const CourseToastLine({super.key, required this.text, required this.opaque});

  final String? text;
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final String? message = text;
    if (message == null) return const SizedBox.shrink();
    final AppColors colors = AppColors.of(context);
    return AnimatedOpacity(
      opacity: opaque ? 1 : 0,
      duration: kCourseToastFade,
      child: Container(
        color: colors.accentFaint,
        padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.s12, vertical: AppDimens.s4),
        child: Row(
          children: <Widget>[
            Icon(Icons.check_circle_outline, size: 16, color: colors.accent),
            const SizedBox(width: AppDimens.s8),
            Expanded(
              child: Text(
                message,
                key: const ValueKey<String>('course-toast'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.meta.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
