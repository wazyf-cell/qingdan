import 'package:flutter/widgets.dart';

import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';

/// 长按快捷方式 / 小组件点击 → 页签与详情（v1.0.6）。
///
/// 与 `NotificationRouter` 同形：装配层没有 `BuildContext`，所以这里只写模型
/// 状态；推全屏详情页由 `AppShell` 监听 [TaskPaneModel.detailPageRequest] 完成。
/// 路由字符串由原生 `AppNav.kt` 从 `qingdan://shortcut/<route>` 取出，未知路由
/// 一律忽略（旧版 APK 收到新路由不该崩）。
class NavRouter {
  NavRouter({this.sidebar, this.pane, this.navigatorKey});

  final SidebarModel? sidebar;
  final TaskPaneModel? pane;

  /// 根 Navigator。快捷方式可能是在「设置 → 通用」这类推上来的页面上点的：
  /// 不先弹回去，页签切换就发生在被盖住的那层，用户看到「点了没反应」
  /// （2026-10-23 模拟器抓到）。
  final GlobalKey<NavigatorState>? navigatorKey;

  /// 最近收到的一条路由（测试与排查用，不含凭据）。
  String? lastRoute;

  void handle(String? route) {
    lastRoute = route;
    if (route == null || route.isEmpty) return;

    navigatorKey?.currentState?.popUntil((Route<dynamic> r) => r.isFirst);

    switch (route) {
      case 'new_task':
        sidebar?.selectTab(ShellTab.tasks);
        // 从别的页签切过来时输入框这一帧才挂上；等到帧末再聚焦，否则 requestFocus
        // 落在一个还没 attach 的 FocusNode 上，表现就是「点了快捷方式但键盘没出来」。
        WidgetsBinding.instance
            .addPostFrameCallback((_) => pane?.focusQuickAdd());
      case 'today':
        // 先判断再调：`select` 对同值早退，停在「设置」页签时点「今天」会没反应。
        if (sidebar?.selectedId == kSmartToday) {
          sidebar?.selectTab(ShellTab.tasks);
        } else {
          sidebar?.select(kSmartToday);
        }
      case 'course':
        sidebar?.selectTab(ShellTab.course);
      case 'chaoxing':
        sidebar?.selectTab(ShellTab.chaoxing);
      default:
        if (route.startsWith('task:')) {
          final String id = route.substring('task:'.length);
          if (id.isEmpty) return;
          sidebar?.selectTab(ShellTab.tasks);
          pane?.openDetailFromNotification(id);
        }
    }
  }
}
