// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 应用生命周期观察者 + 通知点击路由（M6-C2 §6）。项目里的**第一个**
/// `WidgetsBindingObserver`：此前没有任何地方观察 `resumed`，所以「从后台回到
/// 前台要重排提醒」这个触发点无处可挂。
///
/// 拆成本文件而不是塞进 `main.dart`：`main` 已经接近 300 行红线，而这两件事
/// （生命周期、payload 路由）都是装配层的胶水，与彼此无关、与业务无关。
library;

import 'package:flutter/widgets.dart';

import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/notify/reminder_plan.dart' show kChaoxingPayload;

/// 回到前台 → [onResume]。冷启动时 Flutter 也会发一次 `resumed`，多出的那一次
/// 由 `ReminderCoordinator` 的 500ms 防抖并掉，不会重复排程。
class AppLifecycleObserver with WidgetsBindingObserver {
  AppLifecycleObserver({required this.onResume});

  final VoidCallback onResume;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// 通知点击后的落点（§C2「点击行为」）。
///
/// payload 的形状由 `reminder_plan.dart` 决定：清单提醒 = **任务 id 原文**，
/// 学习通提醒 = 字面量 `chaoxing`。两者不会撞车（任务 id 是
/// `IdGenerator.next()` 的 18 字符 base36 串）。
///
/// 已知边界：窄屏的「全屏详情页」由 `AppShell` 在点行时 push，装配层拿不到那个
/// 入口，所以这里只做「切到清单页签 + 把该任务设为详情选中」——三栏桌面形态
/// 立刻能看到详情，手机形态能看到高亮行，再点一次即进详情。
class NotificationRouter {
  NotificationRouter({this.sidebar, this.pane});

  final SidebarModel? sidebar;
  final TaskPaneModel? pane;

  /// 最近一次收到的 payload（测试与排查用；不含任何凭据）。
  String? lastPayload;

  void handle(String? payload) {
    lastPayload = payload;
    if (payload == null || payload.isEmpty) return;
    if (sidebar == null && pane == null) return;
    if (payload == kChaoxingPayload) {
      sidebar?.selectTab(ShellTab.chaoxing);
      return;
    }
    sidebar?.selectTab(ShellTab.tasks);
    pane?.openDetail(payload);
  }
}
