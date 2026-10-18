import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'settings_model.dart';
import 'sync_section.dart';

/// 设置 · 数据与同步节（M6-C C1）：同步配置 + 回收站自动清空。
///
/// 为什么把两件事放一节：它们回答的是同一个问题——「我的数据会去哪、什么时候真的没了」。
/// 原来同步是独立一节、回收站阈值根本没有入口（只有调度器在读 prefs），
/// 用户想改「多久清空」只能等 A 批那句「设置里可选」兑现。
class DataSection extends StatelessWidget {
  const DataSection({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text('数据与同步',
              style:
                  AppTypography.panelTitle.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppDimens.s16),
        ],
        const SyncSection(showTitle: false),
        const SizedBox(height: AppDimens.s24),
        Text('回收站自动清空',
            style:
                AppTypography.meta.copyWith(color: colors.textSecondary)),
        const SizedBox(height: AppDimens.s8),
        const _PurgeChoices(),
        const SizedBox(height: AppDimens.s4),
        Text('超过这个天数的已删除任务，会在应用打开时彻底删除。'
            '只有任务有回收站，课程删除即消失，不受这里影响。',
            style:
                AppTypography.meta.copyWith(color: colors.textFaint, height: 1.4)),
      ],
    );
  }
}

/// 四档单选（永不 / 7 / 30 / 90 天）。不做自由输入：合法值只有这四个，
/// 让输入框校验「15 天」这种值没有任何意义。
class _PurgeChoices extends StatelessWidget {
  const _PurgeChoices();

  static String labelOf(int days) => days == 0 ? '永不' : '$days 天';

  @override
  Widget build(BuildContext context) {
    final SettingsModel model = context.watch<SettingsModel>();
    return SegmentedButton<int>(
      key: const ValueKey<String>('trash-purge-days'),
      showSelectedIcon: false,
      segments: SettingsModel.kTrashPurgeDaysChoices
          .map((int d) =>
              ButtonSegment<int>(value: d, label: Text(labelOf(d))))
          .toList(),
      selected: <int>{model.trashPurgeDays},
      onSelectionChanged: (Set<int> next) =>
          model.setTrashPurgeDays(next.first),
    );
  }
}
