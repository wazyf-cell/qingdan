import 'package:flutter/material.dart';

/// 窄屏（<720dp）底部导航的四个页签（M5 定案第 1 条）。
///
/// 桌面三栏与 720–1039 图标栏**不用它**——那两种形态仍是侧栏/图标栏导航，
/// 只有手机换成底部栏。标签文案定案第 3 条：tab 上写「学习通」，
/// 页面内标题保留全名「学习通待办」（5 个字在 411/4≈103dp 会挤或换行）。
enum ShellTab {
  tasks('清单', Icons.list_alt),
  chaoxing('学习通', Icons.school_outlined),
  course('课表', Icons.view_week_outlined),
  settings('设置', Icons.settings_outlined);

  const ShellTab(this.label, this.icon);

  final String label;
  final IconData icon;
}
