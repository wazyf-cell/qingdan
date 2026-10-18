import 'package:flutter/material.dart';

import 'about_section.dart';
import 'appearance_section.dart';
import 'chaoxing_section.dart';
import 'course_section.dart';
import 'data_section.dart';
import 'general_section.dart';
import 'notify_section.dart';

/// 设置树的一级条目（M6-C C1，2026-10-18 用户批准的结构）。
enum SettingsSectionId { appearance, notify, data, course, chaoxing, general, about }

/// 一节：id + 图标 + 标题 + 副文案 + 内容构造。
///
/// **手机一级页与桌面对话框左栏共用这一份**——之前两边各写一遍，加一节要改两处、
/// 顺序还会漂；现在只有这里能加节。
class SettingsEntry {
  const SettingsEntry({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.content,
  });

  final SettingsSectionId id;
  final IconData icon;
  final String title;

  /// 一级页那一行副文案：要让用户在一级就知道东西在哪，不写空话。
  final String subtitle;

  /// `showTitle` 只有桌面对话框需要（右栏没有顶栏，靠节名认节）；
  /// 手机二级页的顶栏已经写了节名，必须传 false，否则两行同名。
  final Widget Function(bool showTitle) content;

  /// 行 key 统一 `settings-<id>`（测试与自动化都认这个，不再手写字符串）。
  String get rowKey => 'settings-${id.name}';
}

/// 顺序即界面顺序：外观 / 通知 / 数据与同步 / 课表 / 学习通 / 通用 / 关于。
List<SettingsEntry> settingsEntries() => const <SettingsEntry>[
      SettingsEntry(
        id: SettingsSectionId.appearance,
        icon: Icons.palette_outlined,
        title: '外观',
        subtitle: '主题、底部角标、手机默认打开的页面',
        content: AppearanceSection.new,
      ),
      SettingsEntry(
        id: SettingsSectionId.notify,
        icon: Icons.notifications_outlined,
        title: '通知',
        subtitle: '系统通知权限、到期与截止提醒、免打扰',
        content: NotifySection.new,
      ),
      SettingsEntry(
        id: SettingsSectionId.data,
        icon: Icons.cloud_outlined,
        title: '数据与同步',
        subtitle: 'WebDAV 配置与测试连接、回收站自动清空',
        content: DataSection.new,
      ),
      SettingsEntry(
        id: SettingsSectionId.course,
        icon: Icons.calendar_today_outlined,
        title: '课表',
        subtitle: '学期与作息；模板、导出在下一批',
        content: CourseSection.new,
      ),
      SettingsEntry(
        id: SettingsSectionId.chaoxing,
        icon: Icons.school_outlined,
        title: '学习通',
        subtitle: '账号状态、重新登录、退出与隐藏列表',
        content: ChaoxingSection.new,
      ),
      SettingsEntry(
        id: SettingsSectionId.general,
        icon: Icons.tune,
        title: '通用',
        subtitle: '语言、后台与省电权限、检查更新',
        content: GeneralSection.new,
      ),
      SettingsEntry(
        id: SettingsSectionId.about,
        icon: Icons.info_outline,
        title: '关于',
        subtitle: '版本、使用说明与开源许可',
        content: AboutSection.new,
      ),
    ];
