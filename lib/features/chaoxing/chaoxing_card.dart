/// 学习通条目卡片，逐字对齐扩展成品的行结构：
/// 课程名（小字）→ 标题 → 截止行（`10-18 22:59 截止（剩23小时49分）`，
/// 过期则只写「已过期」）→ 标签行（待打开 / 未提交 / 已完成 / 类型）。
///
/// 与扩展的唯一刻意差异：不做点击跳转（用户明确不要）；长按 = 隐藏本条。
library;

import 'package:flutter/material.dart';

import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/import/chaoxing/chaoxing_time.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'chaoxing_grouping.dart';

class ChaoxingCard extends StatelessWidget {
  const ChaoxingCard({super.key, required this.row, required this.now, required this.onHide});

  final ChaoxingRow row;
  final DateTime now;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final ChaoxingTask t = row.task;
    final ChaoxingUrgency u = urgencyOf(t.dueAt, now);
    // 只有「期限内且有截止」的待办上底色：1 天内淡红、3 天内淡黄、更晚淡绿
    // （用户 2026-10-17 指定）。已完成/已结束/未开始、以及没有截止的条目不上色。
    // 判定抽到 `showsUrgencyTint`：隐藏确认框用同一个函数，两处不会漂（M6B §B5）。
    final bool live = showsUrgencyTint(t, now);
    final Color? tint = !live
        ? null
        : u == ChaoxingUrgency.urgent
            ? colors.dueUrgentBg
            : u == ChaoxingUrgency.soon
                ? colors.dueNearBg
                : colors.dueSafeBg;
    // 底色只能做到「不压垮文字对比度」的极限（见 app_colors 注释），辨识度靠
    // 这条 6dp 竖条补——竖条是图形档，浅底允许用满饱和的语义色。
    final Color? stripe = !live
        ? null
        : u == ChaoxingUrgency.urgent
            ? colors.overdue
            : u == ChaoxingUrgency.soon
                ? colors.priorityMedium
                : colors.success;
    return InkWell(
      onLongPress: onHide,
      child: Container(
        decoration: BoxDecoration(
          color: tint,
          border: Border(
            left: BorderSide(
                color: stripe ?? Colors.transparent,
                width: AppDimens.dueStripeWidth),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppDimens.s16, AppDimens.s8, AppDimens.s16, AppDimens.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(t.courseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.meta
                      .copyWith(color: colors.textSecondary)),
              const SizedBox(height: 2),
              Text(t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppTypography.body.copyWith(color: colors.textPrimary)),
              const SizedBox(height: 2),
              _deadline(t, u, colors),
              const SizedBox(height: AppDimens.s4),
              Wrap(
                spacing: AppDimens.s8,
                children: <Widget>[
                  if (t.unread) _tag(context, '待打开'),
                  // 扩展把「待批阅」也显示成「已完成」（脚本 :172/:828 同判），
                  // 这里跟它一致；原始状态仍留在 serverStatus 里供逻辑用。
                  _tag(context, t.serverDone
                      ? '已完成'
                      : (t.serverStatus ?? row.state.label)),
                  if (t.serverStatus == null) _tag(context, t.kind),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deadline(ChaoxingTask t, ChaoxingUrgency u, AppColors colors) {
    if (!t.ongoing) {
      return Text('已过期',
          style: AppTypography.meta.copyWith(color: colors.textSecondary));
    }
    if (t.dueAt == null) {
      return Text('无截止时间',
          style: AppTypography.meta.copyWith(color: colors.textSecondary));
    }
    return Text(
      formatDeadlineLine(t.dueAt!, now),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.meta.copyWith(
        color: u == ChaoxingUrgency.urgent || u == ChaoxingUrgency.overdue
            ? colors.overdue
            : u == ChaoxingUrgency.soon
                ? colors.textPrimary
                : colors.textSecondary,
        fontWeight: u == ChaoxingUrgency.urgent ? FontWeight.w600 : null,
      ),
    );
  }

  Widget _tag(BuildContext context, String text) {
    final AppColors colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: AppTypography.meta.copyWith(color: colors.textSecondary)),
    );
  }
}
