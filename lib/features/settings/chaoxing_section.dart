/// 设置 · 学习通节（M6-C §C5）：账号状态 + 三个动作 + 两段诚实边界说明。
///
/// 三个动作**全部复用面板那一条实现路径**（`chaoxing_actions.dart`），本节不重写
/// 登录/退出逻辑：两处各写一份必漂（面板改版时就漂过一次「退出没清 cookie jar」）。
/// 状态卡只显示登录态与最近抓取时刻，**不显示 cookie 或任何凭据片段**（总纲铁律 6）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/chaoxing/chaoxing_actions.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 本节的 key。`ChaoxingKeys` 只收面板内部的 id，设置域的 id 写在这里
/// （那两个文件本轮归别的批次所有，不动它）。
const String kChaoxingSectionStatusKey = 'cx-set-status';
const String kChaoxingSectionReloginKey = 'cx-set-relogin';
const String kChaoxingSectionLogoutKey = 'cx-set-logout';
const String kChaoxingSectionHiddenKey = 'cx-set-hidden';

class ChaoxingSection extends StatelessWidget {
  const ChaoxingSection({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final ChaoxingModel model = context.watch<ChaoxingModel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text('学习通',
              style:
                  AppTypography.panelTitle.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppDimens.s8),
        ],
        _statusCard(colors, model),
        const SizedBox(height: AppDimens.s8),
        _action(
          key: kChaoxingSectionReloginKey,
          icon: Icons.login_outlined,
          title: '重新登录',
          subtitle: '打开超星登录页换一次凭据，成功后自动刷新待办',
          onTap: () => confirmAndRelogin(context),
        ),
        _action(
          key: kChaoxingSectionHiddenKey,
          icon: Icons.visibility_off_outlined,
          title: '隐藏列表',
          subtitle: '查看被隐藏的作业与活动，可逐条恢复',
          trailing: '${model.hiddenEntries.length} 项',
          onTap: () => openChaoxingHiddenList(context),
        ),
        _action(
          key: kChaoxingSectionLogoutKey,
          icon: Icons.logout,
          title: '退出登录',
          subtitle: '清除凭据，并取消已排的学习通到期提醒',
          onTap: () => confirmAndLogout(context),
        ),
        _note(colors, '刷新只在两处：① 每次打开应用后第一次进入学习通页（自动一次）；'
            '② 你在学习通页点刷新按钮。没有后台定时刷新——本应用不在后台常驻，'
            '也没有自建服务端。'),
        _note(colors, '学习通待办只是本机里的一份外部快照：**不写入应用数据库、'
            '不参与设备间同步**，所以另一台设备要自己登录一次才看得到。'
            '退出登录会清除凭据与提醒快照。'),
      ],
    );
  }

  Widget _statusCard(AppColors colors, ChaoxingModel model) {
    return Container(
      key: const ValueKey<String>(kChaoxingSectionStatusKey),
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.s12, vertical: AppDimens.s12),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppDimens.radiusMobile),
      ),
      child: Row(
        children: <Widget>[
          Icon(model.loggedIn ? Icons.account_circle : Icons.account_circle_outlined,
              size: 26,
              color: model.loggedIn ? colors.success : colors.textFaint),
          const SizedBox(width: AppDimens.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(model.loggedIn ? '已登录' : '未登录',
                    style:
                        AppTypography.body.copyWith(color: colors.textPrimary)),
                const SizedBox(height: AppDimens.s4),
                // 只说时刻，不说凭据：这一行会被截图，也可能被用户念给别人听。
                Text('最近抓取：${_fetchedAt(model.fetchedAt)}',
                    style: AppTypography.meta
                        .copyWith(color: colors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required String key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? trailing,
  }) {
    return ListTile(
      key: ValueKey<String>(key),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
      leading: Icon(icon, size: 20),
      title: Text(title),
      subtitle: Text(subtitle, style: AppTypography.meta),
      trailing: trailing == null
          ? const Icon(Icons.chevron_right, size: 20)
          : Text(trailing, style: AppTypography.meta),
      onTap: onTap,
    );
  }

  static String _fetchedAt(DateTime? at) {
    if (at == null) return '从未抓取';
    final String m = at.month.toString().padLeft(2, '0');
    final String d = at.day.toString().padLeft(2, '0');
    final String hh = at.hour.toString().padLeft(2, '0');
    final String mm = at.minute.toString().padLeft(2, '0');
    return '${at.year}-$m-$d $hh:$mm';
  }

  static Widget _note(AppColors colors, String text) => Padding(
        padding: const EdgeInsets.only(top: AppDimens.s8),
        child: Text(text,
            style:
                AppTypography.meta.copyWith(color: colors.textFaint, height: 1.4)),
      );
}
