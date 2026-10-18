import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';

import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/chaoxing/chaoxing_pane.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/features/settings/settings_page.dart';
import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/quick_compose_sheet.dart';
import 'package:qingdan/features/tasks/tasks_page.dart';
import 'package:qingdan/theme/app_colors.dart';

import 'mobile_top_bar.dart';

/// 窄屏（<720dp）壳：56dp 顶栏 + 底部 4 页签（M5 定案第 1、5 条）。
///
/// 抽屉在本形态**彻底取消**：清单切换改走清单页的半屏面板（S2），回收站进
/// 右上 ⋮（S2），同步状态提到顶栏右侧（原来必须开抽屉才看得到）。桌面三栏与
/// 720–1039 图标栏不受影响——需求规格书 :172 的「列表 ↔ 详情」两级页面照旧，
/// 详情仍是推上来的全屏页。
class NarrowShell extends StatelessWidget {
  const NarrowShell({super.key, required this.onOpenDetailPage});

  /// 点任务行时推全屏详情页的回调（由 [AppShell] 提供，窄屏没有内嵌详情面板）。
  final VoidCallback onOpenDetailPage;

  @override
  Widget build(BuildContext context) {
    final SidebarModel model = context.watch<SidebarModel>();
    final ShellTab tab = model.tab;
    return Scaffold(
      appBar: const MobileTopBar(),
      // 定案第 9 条：只用 Flutter 内置淡入，不引动画依赖。
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: Container(
          key: ValueKey<ShellTab>(tab),
          child: switch (tab) {
            ShellTab.tasks =>
              TasksPage(onOpenDetailPage: onOpenDetailPage),
            ShellTab.chaoxing => const ChaoxingPane(),
            ShellTab.course => const CoursePane(),
            ShellTab.settings => const SettingsPage(),
          },
        ),
      ),
      // 2026-10-18 定案（第二轮改）：窄屏清单页右下角的「＋」开**快捷添加抽屉**
      // （能挑到期 / 开始 / 优先级 / 清单）；顶部那个输入框是「一行文本 + 自然语言
      // 日期」的快建，两者入口不同、写路径同一条（TaskPaneModel.createQuickAdd）。
      // 回收站没有输入框也没有必要，故不出现；其余页签也不给。
      floatingActionButton:
          tab == ShellTab.tasks && model.selectedId != kTrash
              ? FloatingActionButton(
                  key: const ValueKey<String>('add-task'),
                  tooltip: '添加待办',
                  onPressed: () => showQuickCompose(context),
                  child: const Icon(Icons.add),
                )
              : null,
      bottomNavigationBar: NavigationBar(
        // 四个标签都常驻：默认 onlyShowSelected 会让未选中的页签只剩图标，
        // 用户看不出底部一共有几个去处（也浪费 2-3 个汉字的宽度预算）。
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: tab.index,
        onDestinationSelected: (int i) {
          // 定案第 9 条：只用 Flutter 内置触感，不引动画依赖。
          HapticFeedback.selectionClick();
          model.selectTab(ShellTab.values[i]);
        },
        destinations: <NavigationDestination>[
          for (final ShellTab t in ShellTab.values)
            NavigationDestination(
                label: t.label, icon: _badgeFor(t, context, model)),
        ],
      ),
    );
  }

  /// 页签角标（M5 定案第 10 条）：清单 = 今天未完成数；学习通 = 待办条数，
  /// 且 24 小时内有到期时换成红底。开关在「设置 · 通用」里。
  ///
  /// 学习通的数字**停在最后一次拉取**（外部快照刻意不后台刷），这一点已经
  /// 写在通用页的说明里，不是这里的 bug。
  static Widget _badgeFor(
      ShellTab t, BuildContext context, SidebarModel model) {
    final SettingsModel settings = context.watch<SettingsModel>();
    final int count = !settings.showBadges
        ? 0
        : switch (t) {
            ShellTab.tasks => model.todayCount,
            ShellTab.chaoxing => context.watch<ChaoxingModel>().todoCount,
            ShellTab.course || ShellTab.settings => 0,
          };
    if (count <= 0) return Icon(t.icon);
    final bool urgent = t == ShellTab.chaoxing &&
        context.watch<ChaoxingModel>().dueSoonCount > 0;
    final AppColors colors = AppColors.of(context);
    return Badge.count(
      count: count,
      // 必须显式给色：`Badge` 的默认底色就是 `colorScheme.error`（红），
      // 不写这一行「普通计数」和「24 小时内到期」长得一模一样，红就失去意义了
      //（2026-10-18 模拟器走查抓到的）。
      backgroundColor: urgent ? colors.overdue : colors.accent,
      child: Icon(t.icon),
    );
  }
}
