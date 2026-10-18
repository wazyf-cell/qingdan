import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:qingdan/features/settings/settings_dialog.dart";
import "package:qingdan/sync/sync_report.dart";
import "package:qingdan/sync/sync_status.dart";
import "package:qingdan/theme/app_colors.dart";
import "package:qingdan/theme/app_dimens.dart";
import "package:qingdan/theme/app_typography.dart";
import "sync_status_model.dart";

/// 侧栏底部 28dp 同步状态槽（M3 §5.2，替换 M1 的透明占位）。
///
/// 六态由 [SyncStatusKind] 驱动（§5.1）；点开是 §5.3 的详情卡。
/// 「同步中」不做旋转动画（M1 定案不做过渡动画），图标 + 文本表态即够。
class SyncSlot extends StatelessWidget {
  const SyncSlot({super.key, this.compact = false});

  /// 紧凑态：两栏形态的 56dp 图标栏放不下文字，只画状态图标，文案进 tooltip。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final SyncStatusModel model = context.watch<SyncStatusModel>();
    final AppColors colors = AppColors.of(context);
    final _SlotVisual visual = _visualFor(model.status, colors);

    return SizedBox(
      height: AppDimens.syncSlotHeight,
      child: InkWell(
        onTap: () => _openDetail(context, model),
        hoverColor: colors.surfaceHigh,
        child: compact
            ? Tooltip(
                message: visual.text,
                child: Center(
                    child: _leading(model.status, colors, visual.color)),
              )
            : Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppDimens.s12),
                child: Row(
                  children: <Widget>[
                    _leading(model.status, colors, visual.color),
                    const SizedBox(width: AppDimens.s8),
                    Expanded(
                      child: Text(
                        visual.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppTypography.meta.copyWith(color: visual.color),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// 12dp 实心圆点（空闲）或 16dp 状态图标。
  static Widget _leading(
      SyncStatus status, AppColors colors, Color color) {
    if (status.kind == SyncStatusKind.idle) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    return Icon(_iconFor(status.kind), size: 16, color: color);
  }

  static IconData _iconFor(SyncStatusKind kind) => switch (kind) {
        SyncStatusKind.unconfigured => Icons.cloud_off,
        SyncStatusKind.running => Icons.sync,
        SyncStatusKind.failed => Icons.sync_problem,
        SyncStatusKind.credentialsInvalid => Icons.cloud_off,
        SyncStatusKind.rateLimited => Icons.hourglass_empty,
        SyncStatusKind.idle => Icons.cloud_done,
      };

  static _SlotVisual _visualFor(SyncStatus status, AppColors colors) {
    return switch (status.kind) {
      SyncStatusKind.unconfigured =>
        _SlotVisual("同步未配置", colors.textFaint),
      SyncStatusKind.running => _SlotVisual("同步中…", colors.accent),
      SyncStatusKind.idle => _SlotVisual(
          "上次同步 ${_hhmm(status.lastSuccessAt)}", colors.success),
      SyncStatusKind.failed =>
        _SlotVisual("同步失败 · 点击查看", colors.overdue),
      SyncStatusKind.credentialsInvalid =>
        _SlotVisual("需要重新配置", colors.overdue),
      SyncStatusKind.rateLimited => _SlotVisual(
          "限流 · ${_hhmm(status.retryAt)} 恢复", colors.textSecondary),
    };
  }

  static Future<void> _openDetail(
      BuildContext context, SyncStatusModel model) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "关闭同步详情",
      barrierColor: const Color(0x66000000),
      transitionDuration: Duration.zero,
      pageBuilder: (BuildContext ctx, _, _) =>
          Center(child: _SyncDetailCard(model: model)),
    );
  }
}

class _SlotVisual {
  const _SlotVisual(this.text, this.color);

  final String text;
  final Color color;
}

/// 详情卡（§5.3）：360×320 居中卡，内容 + [立即同步] [打开设置]。
class _SyncDetailCard extends StatelessWidget {
  const _SyncDetailCard({required this.model});

  final SyncStatusModel model;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final SyncStatus status = model.status;
    final SyncReport? report = status.lastReport;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
      ),
      child: Container(
        width: 360,
        height: 320,
        padding: const EdgeInsets.all(AppDimens.s16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
          boxShadow: AppDimens.overlayShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text("同步详情",
                style: AppTypography.panelTitle
                    .copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppDimens.s12),
            _row(colors, "上次成功",
                status.lastSuccessAt == null
                    ? "从未成功"
                    : _dateTime(status.lastSuccessAt!)),
            _row(colors, "上次结果", _reportText(report)),
            _row(colors, "最近错误",
                status.lastError?.toString() ?? "（无）"),
            _row(colors, "本窗口请求",
                "${model.requestsUsedInWindow} / 600"),
            if (model.deviceId != null)
              _row(colors, "设备", _shortId(model.deviceId!)),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("关闭"),
                ),
                const SizedBox(width: AppDimens.s4),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showSettingsDialog(context);
                  },
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text("打开设置"),
                ),
                const SizedBox(width: AppDimens.s4),
                FilledButton.icon(
                  onPressed: status.kind == SyncStatusKind.running
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          model.syncNow();
                        },
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text("立即同步"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(AppColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(label,
                style:
                    AppTypography.meta.copyWith(color: colors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.meta.copyWith(color: colors.textPrimary)),
          ),
        ],
      ),
    );
  }

  static String _reportText(SyncReport? report) {
    if (report == null) return "（无）";
    final String head = report.errors.isEmpty ? "成功" : "有错误";
    return "$head ↑${report.uploaded} ↓${report.downloaded} "
        "合并${report.merged} 请求${report.requests}";
  }
}

String _two(int v) => v.toString().padLeft(2, "0");

String _hhmm(DateTime? t) {
  if (t == null) return "--:--";
  final DateTime local = t.toLocal();
  return "${_two(local.hour)}:${_two(local.minute)}";
}

String _dateTime(DateTime t) {
  final DateTime local = t.toLocal();
  return "${_two(local.month)}-${_two(local.day)} ${_hhmm(local)}";
}

String _shortId(String id) =>
    id.length <= 8 ? id : "${id.substring(0, 8)}…";
