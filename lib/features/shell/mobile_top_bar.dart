import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/shell/sidebar/sync_slot.dart';
import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 移动形态（<720dp）的 56dp 顶栏（§2.6：页标题 + 同步状态）。
///
/// M5 起本形态不再有抽屉（底部 4 页签接管主导航），所以这里**没有汉堡按钮**；
/// 取而代之把同步状态槽提到顶栏右侧——原来它在抽屉里，手机上不开抽屉就看不见。
/// 设计稿那一行的「搜索」至今没有实装，界面也不给空壳入口，理由见下面 actions
/// 里那段注释。
class MobileTopBar extends StatelessWidget implements PreferredSizeWidget {
  const MobileTopBar({super.key});

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
        // 顶栏**不放搜索入口**（2026-10-19 定案）。F10「按标题与备注搜索」只有
        // 数据层（`TaskDao.search`，已被 `dao_task_test` 钉住），界面一条路径都
        // 没有：清单页页头是三个图标按钮 + 视图 chips，没有输入框，学习通那个
        // 搜索只在它自己的筛选弹层里。原先这颗 `onPressed: null` 的放大镜是
        // 「点了没反应」的死图标，而任何诚实的 tooltip 都得承诺一个不存在的
        // 输入框——按「占位要么说清原因，要么别出现」整颗删掉。要做 F10 的时候
        // 连带实装界面再把它加回来，别再留空壳。
        SizedBox(width: AppDimens.s8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: colors.divider),
      ),
    );
  }
}
