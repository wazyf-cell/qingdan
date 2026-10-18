import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/features/settings/settings_dialog.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'sidebar_actions.dart';
import 'sidebar_model.dart';
import 'sidebar_tiles.dart';
import 'sync_slot.dart';
import 'sync_status_model.dart';

/// 内置清单名（§2.1：seed 行「收集箱」不可删，名称后缀标注）。
const String kInboxName = '收集箱';

/// 侧栏（§2.1 线框）：智能清单组（4 项固定）→ 用户清单组 → ＋新建清单 →
/// 🗑 回收站 → ⚙ 设置 → 底部 28dp 同步状态槽（§1.8，M1 透明占位）。
///
/// 项规格（§1.4）：高 32dp、左内边距 16dp、图标-文字间距 8dp、
/// 右侧计数 11sp/w500（未完成数；「已完成」为累计完成数）。
/// 选中态：accentFaint 行底 + accent 图标文字。
class SidebarView extends StatelessWidget {
  const SidebarView({super.key});

  /// 侧栏项点击：先执行动作，再收起抽屉。
  ///
  /// Flutter 的 `Drawer` 选中后不会自动关闭，Android 真机实测点「回收站」后
  /// 视图已切换、抽屉却仍盖在屏幕上，必须再手动滑走。桌面形态本无抽屉，
  /// `closeDrawer()` 内有 `hasDrawer && isDrawerOpen` 守卫，此处即空转。
  static void _tap(BuildContext context, VoidCallback action) {
    action();
    Scaffold.maybeOf(context)?.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final SidebarModel model = context.watch<SidebarModel>();

    return Container(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: model.error != null
                ? ErrorPane(message: model.error!)
                : ListView(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppDimens.s8),
                    children: <Widget>[
                      const SectionLabel(text: '智能清单'),
                      SidebarNavTile(
                        icon: Icons.wb_sunny_outlined,
                        label: '今天',
                        count: model.todayCount,
                        selected: model.selectedId == kSmartToday,
                        colors: colors,
                        onTap: () =>
                            _tap(context, () => model.select(kSmartToday)),
                      ),
                      SidebarNavTile(
                        icon: Icons.date_range_outlined,
                        label: '最近 7 天',
                        count: model.next7Count,
                        selected: model.selectedId == kSmartNext7,
                        colors: colors,
                        onTap: () =>
                            _tap(context, () => model.select(kSmartNext7)),
                      ),
                      SidebarNavTile(
                        icon: Icons.layers_outlined,
                        label: '所有',
                        count: model.allCount,
                        selected: model.selectedId == kSmartAll,
                        colors: colors,
                        onTap: () =>
                            _tap(context, () => model.select(kSmartAll)),
                      ),
                      SidebarNavTile(
                        icon: Icons.check_circle_outline,
                        label: '已完成',
                        count: model.completedCount,
                        selected: model.selectedId == kSmartCompleted,
                        colors: colors,
                        onTap: () =>
                            _tap(context, () => model.select(kSmartCompleted)),
                      ),
                      SidebarDivider(colors: colors),
                      // M4a 定案 5：课表入口与任务视图并列，三种形态同源。
                      const SectionLabel(text: '视图'),
                      SidebarNavTile(
                        icon: Icons.view_week_outlined,
                        label: '课表',
                        selected: model.selectedId == kCourseWeek,
                        colors: colors,
                        onTap: () =>
                            _tap(context, () => model.select(kCourseWeek)),
                      ),
                      // 学习通待办：外部只读快照，不进本地任务表。
                      SidebarNavTile(
                        icon: Icons.school_outlined,
                        label: '学习通',
                        selected: model.selectedId == kChaoxing,
                        colors: colors,
                        onTap: () =>
                            _tap(context, () => model.select(kChaoxing)),
                      ),
                      SidebarDivider(colors: colors),
                      const SectionLabel(text: '我的清单'),
                      if (!model.loaded)
                        Padding(
                          padding:
                              const EdgeInsets.only(left: 16, top: 8),
                          child: Text(
                            '加载中…',
                            style: AppTypography.meta
                                .copyWith(color: colors.textFaint),
                          ),
                        )
                      else
                        for (final TaskList list in model.lists)
                          SidebarListTile(
                            list: list,
                            inboxName: kInboxName,
                            count: model.countFor(list.id),
                            selected: model.selectedId == list.id,
                            colors: colors,
                            onTap: () =>
                                _tap(context, () => model.select(list.id)),
                          ),
                      SidebarNavTile(
                        icon: Icons.add,
                        label: '新建清单',
                        colors: colors,
                        onTap: () => _tap(
                            context, () => showCreateListDialog(context, model)),
                      ),
                      SidebarDivider(colors: colors),
                      SidebarNavTile(
                        icon: Icons.delete_outline,
                        label: '回收站',
                        selected: model.selectedId == kTrash,
                        colors: colors,
                        onTap: () => _tap(context, () => model.select(kTrash)),
                      ),
                      SidebarNavTile(
                        icon: Icons.settings_outlined,
                        label: '设置',
                        colors: colors,
                        onTap: () =>
                            _tap(context, () => showSettingsDialog(context)),
                      ),
                    ],
                  ),
          ),
          // §1.8 / M3 §5.2：28dp 同步状态槽；未装配 SyncStatusModel 时留占位。
          if (context.watch<SyncStatusModel?>() != null)
            const SyncSlot()
          else
            const SizedBox(height: AppDimens.syncSlotHeight),
        ],
      ),
    );
  }
}
