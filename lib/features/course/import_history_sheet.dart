import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_freshness.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 最近导入历史（M6-A A8）：点顶部那行「上次更新 / 导入时间」弹出。
///
/// 数据来自 `import_batches`，**本地簿记、不参与同步**（2026-10-10 定案 3），
/// 所以这份历史是「这台设备导入过什么」，不是「账号里导入过什么」。
Future<void> showImportHistorySheet(
  BuildContext context, {
  required List<ImportBatch> batches,
  required bool isMobile,
}) {
  final Widget body = _ImportHistory(batches: batches);
  return isMobile
      ? showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6),
          builder: (BuildContext ctx) => SafeArea(child: body),
        )
      : showDialog<void>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('最近导入'),
            content: SizedBox(width: 420, child: body),
          ),
        );
}

class _ImportHistory extends StatelessWidget {
  const _ImportHistory({required this.batches});

  final List<ImportBatch> batches;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(AppDimens.s16),
      children: <Widget>[
        if (batches.isEmpty)
          const Text('还没有导入记录', style: AppTypography.body)
        else ...<Widget>[
          // 局限必须写在界面上：这张表没有学期列，历史是全局的。
          Text('最多 10 次 · 本表不区分学期，可能混入其他学期的导入',
              style: AppTypography.meta.copyWith(color: colors.textFaint)),
          const SizedBox(height: AppDimens.s8),
          for (final ImportBatch b in batches) _BatchRow(batch: b),
        ],
      ],
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.batch});

  final ImportBatch batch;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return ListTile(
      key: ValueKey<String>('import-batch-${batch.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(batch.fileName,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: AppTypography.body),
      subtitle: Text(
        '${courseStamp(batch.importedAt)} · '
        '新增 ${batch.countImported} · 更新 ${batch.countUpdated} · '
        '跳过 ${batch.countSkipped}',
        style: AppTypography.meta.copyWith(color: colors.textSecondary),
      ),
    );
  }
}
