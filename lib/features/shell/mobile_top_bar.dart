import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/shell/sidebar/sync_slot.dart';
import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 移动形态（<720dp）的 56dp 顶栏（§2.6：页标题 / 搜索 / 同步状态）。
///
/// M5 起本形态不再有抽屉（底部 4 页签接管主导航），所以这里**没有汉堡按钮**；
/// 取而代之把同步状态槽提到顶栏右侧——原来它在抽屉里，手机上不开抽屉就看不见。
class MobileTopBar extends StatelessWidget implements PreferredSizeWidget {
  const MobileTopBar({super.key});

  /// §1.6：工具栏图标 20dp 档。
  static const double _toolbarIcon = 20;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final ShellTab tab = context.watch<SidebarModel>().tab;
    // 「清单」页签显示当前视图名（今天 / 最近 7 天 / 回收站…），其余页签显示页签名。
    final String title = tab == ShellTab.tasks
        ? context.watch<TaskPaneModel>().currentViewName
        : tab.label;
    return AppBar(
      // §1.5：阴影只属于浮层，顶栏一律无 elevation。
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: colors.surface,
      foregroundColor: colors.textSecondary,
      centerTitle: false,
      automaticallyImplyLeading: false,
      titleTextStyle: AppTypography.pageTitle.copyWith(
        fontSize: 17, // §2.6：页标题 20sp → 移动形态 17sp
        color: colors.textPrimary,
      ),
      title: Text(title, key: const ValueKey<String>('topBarTitle')),
      actions: const <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppDimens.s4),
          child: SyncSlot(compact: true),
        ),
        // F10 搜索（P1）：§2.6 规定本形态顶栏只放入口，实装属后续里程碑。
        IconButton(
          tooltip: '搜索',
          icon: Icon(Icons.search, size: _toolbarIcon),
          onPressed: null,
        ),
        SizedBox(width: AppDimens.s8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: colors.divider),
      ),
    );
  }
}
