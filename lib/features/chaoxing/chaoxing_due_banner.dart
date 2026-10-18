import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'chaoxing_model.dart';

/// 「今天」页顶部的学习通到期提示条（M5 定案第 7 条）。
///
/// 学习通条目刻意不并进本地清单（外部只读快照、不同步），所以这里只给一条
/// 可点的提示，点它跳到学习通页签，而不是把外部条目混进本地任务行。
/// 条数为 0（含从未拉取过）时整条不渲染。
class ChaoxingDueBanner extends StatelessWidget {
  const ChaoxingDueBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final int n = context.watch<ChaoxingModel>().dueSoonCount;
    if (n <= 0) return const SizedBox.shrink();
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.listPanePaddingH, 0, AppDimens.listPanePaddingH, AppDimens.s4),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusMobile),
        onTap: () =>
            context.read<SidebarModel>().selectTab(ShellTab.chaoxing),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.s12, vertical: AppDimens.s8),
          decoration: BoxDecoration(
            color: colors.dueUrgentBg,
            borderRadius: BorderRadius.circular(AppDimens.radiusMobile),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.school_outlined,
                  size: 16, color: colors.overdue),
              const SizedBox(width: AppDimens.s8),
              Expanded(
                child: Text(
                  '学习通有 $n 条 24 小时内到期',
                  maxLines: 2,
                  style: AppTypography.meta
                      .copyWith(color: colors.textPrimary),
                ),
              ),
              Text('→',
                  style: AppTypography.meta
                      .copyWith(color: colors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
