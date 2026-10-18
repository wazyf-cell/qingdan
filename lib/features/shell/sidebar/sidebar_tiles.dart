import 'package:flutter/material.dart';

import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 侧栏行组件库（自 sidebar_view.dart 拆出）：
/// 分组头 / 分隔线 / 智能清单与新建回收站行 / 用户清单行 / 通用行 / 错误态。
/// 全部公开（无下划线），供 sidebar_view.dart 与 icon_rail.dart 复用。

/// 分组头（智能清单 / 我的清单）。
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(
            left: AppDimens.s16, top: AppDimens.s8, bottom: AppDimens.s4),
        child: Text(
          text,
          style: AppTypography.groupHeader
              .copyWith(color: AppColors.of(context).textSecondary),
        ),
      );
}

/// 1dp 组间分隔线。
class SidebarDivider extends StatelessWidget {
  const SidebarDivider({super.key, required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.s4),
        child: Container(
            height: 1, color: AppColors.of(context).divider),
      );
}

/// 智能清单 / 新建清单 / 回收站行。
class SidebarNavTile extends StatelessWidget {
  const SidebarNavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
    this.count,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final AppColors colors;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SidebarItemRow(
        colors: colors,
        selected: selected,
        onTap: onTap,
        leading: Icon(icon,
            size: 20,
            color: selected ? colors.accent : colors.textSecondary),
        label: label,
        labelColor: selected ? colors.accent : colors.textPrimary,
        count: count,
      );
}

/// 用户清单行（§2.1：左侧 8×8dp 色点区，M1 全部用分隔线色）。
class SidebarListTile extends StatelessWidget {
  const SidebarListTile({
    super.key,
    required this.list,
    required this.inboxName,
    required this.count,
    required this.colors,
    this.selected = false,
    this.onTap,
  });

  final TaskList list;

  /// 内置清单名（命中时名称后缀「（内置）」）。
  final String inboxName;
  final int count;
  final AppColors colors;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SidebarItemRow(
        colors: colors,
        onTap: onTap,
        selected: selected,
        leading: Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.divider,
          ),
        ),
        label: list.name == inboxName ? '$inboxName（内置）' : list.name,
        labelColor: colors.textPrimary,
        count: count,
      );
}

/// 侧栏项通用行：高 32dp、左内边距 16dp、图标-文字 8dp、右侧计数。
class SidebarItemRow extends StatelessWidget {
  const SidebarItemRow({
    super.key,
    required this.colors,
    required this.leading,
    required this.label,
    required this.labelColor,
    this.count,
    this.selected = false,
    this.onTap,
  });

  final AppColors colors;
  final Widget leading;
  final String label;
  final Color labelColor;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Widget row = SizedBox(
      height: AppDimens.sidebarItemHeight,
      child: Row(
        children: <Widget>[
          SizedBox(width: AppDimens.s16, child: leading),
          const SizedBox(width: AppDimens.s8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  AppTypography.body.copyWith(color: labelColor),
            ),
          ),
          if (count != null)
            Padding(
              padding: const EdgeInsets.only(right: AppDimens.s16),
              child: Text(
                '$count',
                style: AppTypography.counter
                    .copyWith(color: colors.textSecondary),
              ),
            ),
        ],
      ),
    );
    return InkWell(
      onTap: onTap,
      hoverColor: colors.surfaceHigh,
      child: Container(
        color: selected ? colors.accentFaint : null,
        child: row,
      ),
    );
  }
}

/// 侧栏数据加载失败态：完整报错原文呈现，不静默。
class ErrorPane extends StatelessWidget {
  const ErrorPane({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppDimens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('侧栏数据加载失败',
              style: AppTypography.body
                  .copyWith(color: colors.overdue)),
          const SizedBox(height: AppDimens.s8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(message,
                  style: AppTypography.meta
                      .copyWith(color: colors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}
