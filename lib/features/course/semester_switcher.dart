import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 周次行最左边的学期名按钮（M6-D §7.1）。
///
/// 单独成文件的原因：`course_week_header.dart` 已 267 行，把按钮 + 省略号规则
/// + 弹层入口一起塞进去必破 AGENTS.md 的 300 行红线。
///
/// 宽度约束是真约束：移动端 411dp 那一行已经排到只剩 ~123dp 给周次标签
/// （S4b 的「周次标签换行压住星期轴」事故），所以这颗按钮必须自己**让步**：
/// 横向内边距收到 4dp、名字交给 [Flexible] 截断成省略号、`▾` 始终跟在后面。
class SemesterSwitcher extends StatelessWidget {
  const SemesterSwitcher({
    super.key,
    required this.name,
    required this.isMobile,
    this.onTap,
  });

  /// 学期名（模型里的当前学期；空字符串渲染成占位文案，不留空白按钮）。
  final String name;
  final bool isMobile;
  final VoidCallback? onTap;

  static const String _fallback = '未命名学期';

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String label = name.trim().isEmpty ? _fallback : name.trim();
    final double maxWidth =
        isMobile ? kSemesterSwitcherMaxMobile : kSemesterSwitcherMaxDesktop;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: TextButton(
        // key 挂在按钮上：测试点它开面板，同时读里面的 Text 断言文案。
        key: const ValueKey<String>('semester-switcher'),
        // 移动端不给 64dp 最小宽（见文件头），纵向仍守 44dp 行高。
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
          visualDensity: VisualDensity.compact,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: colors.textPrimary,
        ),
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                // key 挂在 Text 上：点的是按钮，读的是这一行，两个断言各取所需。
                key: const ValueKey<String>('semester-switcher-label'),
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.panelTitle
                    .copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: AppDimens.s4),
            Text('▾',
                style: AppTypography.panelTitle
                    .copyWith(color: colors.textFaint, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// 这颗按钮最多能占多宽：桌面 132dp、移动 120dp。
///
/// 再宽就会把「今天」与三个图标按钮推出屏幕（411dp 上更是直接把周次标签挤到
/// 第二行——S4b 的「周次标签换行压住星期轴」事故就是这么来的）。
const double kSemesterSwitcherMaxDesktop = 132;
const double kSemesterSwitcherMaxMobile = 120;

/// 学期域两份弹层共用的外壳（§7.1 面板 / §7.2 新建）：移动 = 半屏底部抽屉，桌面 =
/// 居中弹窗（§2.6 双端形态约定）。[height] 只给需要 `Flexible` 列表的形态。
Future<T?> showSemesterSheetShell<T>(
  BuildContext context, {
  required bool isMobile,
  required Widget Function(BuildContext ctx) body,
  double width = 420,
  double? height,
}) =>
    isMobile
        ? showModalBottomSheet<T>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6),
            builder: (BuildContext ctx) => Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(ctx).bottom,
                  left: AppDimens.s16,
                  right: AppDimens.s16,
                  top: AppDimens.s8),
              child: body(ctx),
            ),
          )
        : showDialog<T>(
            context: context,
            builder: (BuildContext ctx) => AlertDialog(
              insetPadding: const EdgeInsets.all(AppDimens.s32),
              // 给了 height 就把内容钉成那个高度（列表自己带滚动）；没给就让
              // 外壳滚 —— 列表那种含 Flexible 的内容在无界高度里会直接 assert。
              content: SizedBox(
                width: width,
                child: height == null
                    ? SingleChildScrollView(child: body(ctx))
                    : SizedBox(height: height, child: body(ctx)),
              ),
            ),
          );
