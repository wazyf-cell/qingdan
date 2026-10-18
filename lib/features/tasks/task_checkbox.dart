import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 任务勾选框（§3.1）：18dp，未选中 1.5dp 次要文字描边；选中填充主色，
/// 填充动画 120ms（scale 0.8→1.0）。回收站复用行时由外层替换为恢复图标，
/// 不走本组件。
class TaskCheckbox extends StatefulWidget {
  const TaskCheckbox({
    super.key,
    required this.completed,
    required this.onToggle,
    this.size = 18,
  });

  final bool completed;
  final VoidCallback onToggle;
  final double size;

  @override
  State<TaskCheckbox> createState() => _TaskCheckboxState();
}

class _TaskCheckboxState extends State<TaskCheckbox> {
  // 勾选填充动画（§3.1：120ms，scale 0.8→1.0，不做飘落/发光）。
  bool _animate = false;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _animate = true);
        widget.onToggle();
      },
      child: AnimatedScale(
        // 选中瞬间 0.8 → 1.0；取消勾选直接回弹（反向同参数由动画自然覆盖）。
        scale: widget.completed && !_animate ? 1.0 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.completed ? colors.accent : Colors.transparent,
            border: Border.all(
              color: widget.completed ? colors.accent : colors.textSecondary,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: AnimatedScale(
            scale: widget.completed ? 1.0 : 0.8,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Icon(
              Icons.check,
              size: widget.size - 6,
              color: colors.surface,
            ),
          ),
        ),
      ),
    );
  }
}

/// 16dp 子任务勾选框（§2.3，同款样式缩小版）。
class SubtaskCheckbox extends StatelessWidget {
  const SubtaskCheckbox({
    super.key,
    required this.completed,
    required this.onToggle,
  });

  final bool completed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: completed ? colors.accent : Colors.transparent,
          border: Border.all(
            color: completed ? colors.accent : colors.textSecondary,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(AppDimens.radiusDesktop / 2),
        ),
        child: completed
            ? Icon(Icons.check, size: 11, color: colors.surface)
            : null,
      ),
    );
  }
}
