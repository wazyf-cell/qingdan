import 'package:flutter/material.dart';

import 'package:qingdan/platform/system_intents.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 「后台与省电」面板（M6-C C3）：三个系统页入口 + 厂商自启动的文字说明。
///
/// 为什么不做厂商自启动深链：小米 / 华为 / OPPO / vivo 各有一套 activity，
/// 没有标准 action，猜错了就是把用户丢进一个无关页面。所以只给「应用详情页」
/// 这个通用兜底 + 一段手路文字。
///
/// 失败**不用 SnackBar**：本面板是 modal route，SnackBar 画在它下面那层，
/// 用户看不见（课表弹层已经栽过一次）。改成本地一行回执。
Future<void> showPermissionsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) => const SafeArea(
        top: false,
        child: SingleChildScrollView(child: _PermissionsBody()),
      ),
    );

class _PermissionsBody extends StatefulWidget {
  const _PermissionsBody();

  @override
  State<_PermissionsBody> createState() => _PermissionsBodyState();
}

class _PermissionsBodyState extends State<_PermissionsBody> {
  /// 最近一次跳转的结果文案（null = 还没点过）。
  String? _said;

  Future<void> _open(String label, Future<bool> Function() intent) async {
    final bool ok = await intent();
    if (!mounted) return;
    setState(() => _said = ok
        ? null
        : '「$label」打不开：请手动到 系统设置 → 应用 → 清单 里找。'
            '${Theme.of(context).platform == TargetPlatform.windows ? '（Windows 端没有这些系统页，提醒也只在 Android 生效。）' : ''}');
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.s16, 0, AppDimens.s16, AppDimens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('后台与省电', style: AppTypography.panelTitle),
          const SizedBox(height: AppDimens.s12),
          _ActionRow(
            rowKey: 'perm-notification-settings',
            label: '通知设置',
            hint: '系统里本应用的通知开关与通道',
            onOpen: () => _open('通知设置', SystemIntents.openNotificationSettings),
          ),
          _ActionRow(
            rowKey: 'perm-battery-optimization',
            label: '电池优化',
            hint: '在列表里把「清单」设为不优化',
            onOpen: () => _open('电池优化',
                SystemIntents.openBatteryOptimizationSettings),
          ),
          _ActionRow(
            rowKey: 'perm-app-details',
            label: '应用详情页',
            hint: '厂商的自启动 / 省电入口都从这里进',
            onOpen: () => _open('应用详情页', SystemIntents.openAppDetails),
          ),
          if (_said != null)
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.s8),
              child: Text(_said!,
                  key: const ValueKey<String>('perm-said'),
                  style:
                      AppTypography.meta.copyWith(color: colors.overdue)),
            ),
          const SizedBox(height: AppDimens.s16),
          Text('各家手机厂商（小米 / 华为 / OPPO / vivo）的「自启动」入口路径都不一样，'
              '应用没法替你跳过去。常见位置：系统设置 → 应用管理 → 清单 → 自启动 / 电池 → 无限制。',
              style:
                  AppTypography.meta.copyWith(color: colors.textFaint, height: 1.5)),
          const SizedBox(height: AppDimens.s12),
          // 这句是整个提醒设计的诚实边界，规格要求不许省。
          Text('本应用不在后台常驻。所有提醒都排入系统闹钟，应用被杀掉也会响；'
              '但新增或改动的待办，要等你下次打开应用才会重新排程。',
              style:
                  AppTypography.meta.copyWith(color: colors.textSecondary, height: 1.5)),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.rowKey,
    required this.label,
    required this.hint,
    required this.onOpen,
  });

  final String rowKey;
  final String label;
  final String hint;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return ListTile(
      key: ValueKey<String>(rowKey),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label,
          style: AppTypography.body.copyWith(color: colors.textPrimary)),
      subtitle: Text(hint,
          style: AppTypography.meta.copyWith(color: colors.textFaint)),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: onOpen,
    );
  }
}
