import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/settings/settings_dialog.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/shell/sidebar/sync_slot.dart';
import 'package:qingdan/features/shell/sidebar/sync_status_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 两栏形态（720–1039dp）的图标栏：宽 56dp，仅图标入口（§1.7）。
///
/// 图标集合与抽屉/侧栏同源（4 个智能清单 + 回收站 + 设置），选中态与
/// [SidebarModel.selectedId] 联动；底部 28dp 是同步状态槽紧凑态（§1.8）。
/// 「设置」在本形态不可缺：侧栏被收成图标栏后，它是唯一的设置入口。
class IconRail extends StatelessWidget {
  const IconRail({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final SidebarModel model = context.watch<SidebarModel>();
    return Container(
      color: colors.surface,
      child: Column(
        children: <Widget>[
          const SizedBox(height: AppDimens.s8),
          _RailButton(
            icon: Icons.wb_sunny_outlined,
            tooltip: '今天',
            selected: model.selectedId == kSmartToday,
            onTap: () => model.select(kSmartToday),
          ),
          _RailButton(
            icon: Icons.date_range_outlined,
            tooltip: '最近 7 天',
            selected: model.selectedId == kSmartNext7,
            onTap: () => model.select(kSmartNext7),
          ),
          _RailButton(
            icon: Icons.layers_outlined,
            tooltip: '所有',
            selected: model.selectedId == kSmartAll,
            onTap: () => model.select(kSmartAll),
          ),
          _RailButton(
            icon: Icons.check_circle_outline,
            tooltip: '已完成',
            selected: model.selectedId == kSmartCompleted,
            onTap: () => model.select(kSmartCompleted),
          ),
          const SizedBox(height: AppDimens.s8),
          Container(height: 1, color: colors.divider),
          const SizedBox(height: AppDimens.s8),
          _RailButton(
            icon: Icons.view_week_outlined,
            tooltip: '课表',
            selected: model.selectedId == kCourseWeek,
            onTap: () => model.select(kCourseWeek),
          ),
          _RailButton(
            icon: Icons.school_outlined,
            tooltip: '学习通',
            selected: model.selectedId == kChaoxing,
            onTap: () => model.select(kChaoxing),
          ),
          _RailButton(
            icon: Icons.delete_outline,
            tooltip: '回收站',
            selected: model.selectedId == kTrash,
            onTap: () => model.select(kTrash),
          ),
          _RailButton(
            icon: Icons.settings_outlined,
            tooltip: '设置',
            onTap: () => showSettingsDialog(context),
          ),
          const Spacer(),
          // §1.8 / M3 §5.2：28dp 状态槽；未装配 SyncStatusModel 时留占位。
          if (context.watch<SyncStatusModel?>() != null)
            const SyncSlot(compact: true)
          else
            const SizedBox(height: AppDimens.syncSlotHeight),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.s8, vertical: AppDimens.s4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
          hoverColor: colors.surfaceHigh,
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: selected ? colors.accentFaint : null,
              borderRadius:
                  BorderRadius.circular(AppDimens.radiusDesktop),
            ),
            child: Icon(
              icon,
              size: 20,
              color: selected ? colors.accent : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
